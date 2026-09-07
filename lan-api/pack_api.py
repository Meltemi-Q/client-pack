# -*- coding: utf-8 -*-
"""LAN pack API for the community Windows client.

Default: pull develop2, pack, copy installer to NAS. No request parameters.
GET  /           progress page
GET  /api/status JSON
POST /api/pack   start a pack (ignored if already running)
"""
from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

_LAN = Path(__file__).resolve().parent
_CLIENT_PACK_DEFAULT = _LAN.parent
_GEERJI_ALL = _CLIENT_PACK_DEFAULT.parent


def _first_existing(*candidates):
    for raw in candidates:
        if not raw:
            continue
        path = Path(os.path.expandvars(raw))
        if path.exists():
            return path
    return Path(os.path.expandvars(candidates[-1]))


HOST = os.environ.get("PACK_API_HOST", "0.0.0.0")
PORT = int(os.environ.get("PACK_API_PORT", "8765"))
REPO = Path(os.environ.get("PACK_REPO", str(_GEERJI_ALL / "medical_version_client")))
CLIENT_PACK = Path(os.environ.get("PACK_CLIENT_PACK", str(_CLIENT_PACK_DEFAULT)))
NAS_DIR = os.environ.get(
    "PACK_NAS_DIR",
    r"\\nas.golgi-bci.com\软件组共享\最新社区筛查客户端",
)
NAS_DIR_IP = os.environ.get(
    "PACK_NAS_DIR_IP",
    r"\\192.168.0.89\软件组共享\最新社区筛查客户端",
)
NAS_CRED = Path(os.environ.get("PACK_NAS_CRED", str(_LAN / "nas.cred")))
GIT_KEY = Path(os.environ.get("PACK_GIT_KEY", str(_LAN / "id_ed25519_geerji_client")))
GIT_TOKEN = Path(os.environ.get("PACK_GIT_TOKEN", str(_LAN / "git.token")))
GIT_HELPER = Path(os.environ.get("PACK_GIT_HELPER", str(_LAN / "git-credential-geerji.cmd")))
GIT_SSH_URL = "git@github.com:geerji/medical_version_client-.git"
GIT_HTTPS_URL = "https://github.com/geerji/medical_version_client-.git"
LOCAL_OUT = Path(os.environ.get("PACK_LOCAL_OUT", str(_GEERJI_ALL / "_pack_out")))
BRANCH = os.environ.get("PACK_BRANCH", "develop2")
FFMPEG = str(
    _first_existing(
        os.environ.get("GOLGI_FFMPEG"),
        r"%USERPROFILE%\scoop\apps\ffmpeg\current\bin\ffmpeg.exe",
        r"%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe",
    )
)
CONDA_ROOT = _first_existing(
    os.environ.get("PACK_CONDA_ROOT"),
    r"%USERPROFILE%\scoop\apps\miniconda3\current",
    r"%USERPROFILE%\Miniconda3",
)
LOG_DIR = Path(os.environ.get("PACK_API_LOG", str(_LAN / "logs")))
HISTORY_FILE = LOG_DIR / "history.json"
HISTORY_MAX = 20

_lock = threading.Lock()
_history = []
_state = {
    "state": "idle",
    "step": "idle",
    "step_label": "空闲",
    "percent": 0,
    "detail": "还没有开始打包",
    "started_at": None,
    "finished_at": None,
    "installer": None,
    "nas_path": None,
    "local_path": None,
    "commit": None,
    "error": None,
    "log_tail": "",
    "dry": False,
    "caller": None,
    "changes": [],
    "duration": None,
}


def _now():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def set_progress(**kwargs):
    with _lock:
        _state.update(kwargs)
        if "log_tail" in kwargs and kwargs["log_tail"] and len(kwargs["log_tail"]) > 4000:
            _state["log_tail"] = kwargs["log_tail"][-4000:]


def snapshot():
    with _lock:
        st = dict(_state)
        st["history"] = list(_history)
        return st


def _enrich_history_item(item):
    if not item.get("duration"):
        item["duration"] = _duration_text(item.get("started_at"), item.get("finished_at"))
    if item.get("changes") is None:
        item["changes"] = []
    return item


def _load_history():
    if HISTORY_FILE.is_file():
        try:
            data = json.loads(HISTORY_FILE.read_text(encoding="utf-8"))
            if isinstance(data, list):
                return [_enrich_history_item(x) for x in data[:HISTORY_MAX]]
        except Exception:
            pass
    return []


def _save_history():
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    with _lock:
        data = list(_history)
    HISTORY_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")


def _add_history(entry):
    with _lock:
        _history.insert(0, entry)
        del _history[HISTORY_MAX:]
    _save_history()


def _parse_time(text):
    if not text:
        return None
    try:
        return time.mktime(time.strptime(text, "%Y-%m-%d %H:%M:%S"))
    except Exception:
        return None


def _duration_text(start, end):
    t0 = _parse_time(start)
    t1 = _parse_time(end)
    if t0 is None or t1 is None:
        return None
    sec = int(t1 - t0)
    if sec < 0:
        return None
    if sec < 60:
        return "%s秒" % sec
    minutes, seconds = divmod(sec, 60)
    if minutes < 60:
        return "%s分%s秒" % (minutes, seconds)
    hours, minutes = divmod(minutes, 60)
    return "%s小时%s分" % (hours, minutes)


def _commit_hash(text):
    if not text:
        return ""
    return text.strip().split()[0]


def _git_changes(curr_commit):
    curr = _commit_hash(curr_commit)
    if not curr or not (REPO / ".git").exists():
        return []
    prev = ""
    with _lock:
        for item in _history:
            prev = _commit_hash(item.get("commit"))
            if prev:
                break
    cmd = ["git", "log", "--oneline", "-12"]
    if prev and prev != curr:
        cmd = ["git", "log", "--oneline", "-12", "%s..%s" % (prev, curr)]
    else:
        cmd = ["git", "log", "--oneline", "-8", curr]
    proc = subprocess.run(
        cmd,
        cwd=str(REPO),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    lines = [x.strip() for x in (proc.stdout or "").splitlines() if x.strip()]
    return lines[:12]


def _caller_label(handler):
    ip = _client_ip(handler)
    if ip in _local_ips():
        return "本机 %s" % ip
    host = ""
    try:
        host = socket.gethostbyaddr(ip)[0]
    except Exception:
        host = ""
    if host and host != ip:
        return "%s（%s）" % (host, ip)
    return ip


def _history_from_state():
    st = snapshot()
    changes = st.get("changes") or _git_changes(st.get("commit"))
    return {
        "state": st.get("state"),
        "started_at": st.get("started_at"),
        "finished_at": st.get("finished_at"),
        "duration": st.get("duration") or _duration_text(st.get("started_at"), st.get("finished_at")),
        "installer": st.get("installer"),
        "local_path": st.get("local_path"),
        "nas_path": st.get("nas_path"),
        "commit": st.get("commit"),
        "changes": changes,
        "caller": st.get("caller"),
        "detail": st.get("detail"),
        "error": st.get("error"),
        "dry": bool(st.get("dry")),
    }


def _backfill_history_from_files():
    seen = set()
    items = []
    for folder in (LOCAL_OUT, REPO / "dist" / "installer"):
        if not folder.is_dir():
            continue
        for path in folder.glob("*_setup_*.exe"):
            if path.name in seen:
                continue
            seen.add(path.name)
            stamp = None
            m = re.search(r"_(\d{8})_(\d{6})\.exe$", path.name)
            if m:
                stamp = "%s-%s-%s %s:%s:%s" % (
                    m.group(1)[0:4],
                    m.group(1)[4:6],
                    m.group(1)[6:8],
                    m.group(2)[0:2],
                    m.group(2)[2:4],
                    m.group(2)[4:6],
                )
            finished = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(path.stat().st_mtime))
            items.append(
                {
                    "state": "success",
                    "started_at": stamp,
                    "finished_at": finished,
                    "duration": _duration_text(stamp, finished),
                    "installer": path.name,
                    "local_path": str(path),
                    "nas_path": None,
                    "commit": None,
                    "changes": [],
                    "caller": None,
                    "detail": "本机安装包（服务启动时扫到的）",
                    "error": None,
                    "dry": None,
                }
            )
    items.sort(key=lambda x: x.get("started_at") or x.get("finished_at") or "", reverse=True)
    return items[:HISTORY_MAX]


def _local_ips():
    found = {"127.0.0.1", "::1"}
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None):
            ip = info[4][0]
            if ip:
                found.add(ip)
    except Exception:
        pass
    return found


def _client_ip(handler):
    ip = handler.client_address[0]
    if ip.startswith("::ffff:"):
        ip = ip[7:]
    return ip


def _is_owner(handler):
    return _client_ip(handler) in _local_ips()


STEPS = [
    ("pull", "正在拉最新代码", 8),
    ("spec", "正在准备打包 spec", 12),
    ("pyinstaller", "正在用 PyInstaller 打包程序", 70),
    ("inno", "正在打 Inno 安装包", 90),
    ("upload", "正在拷到 NAS", 96),
    ("done", "完成", 100),
]


def _append_log(buf, line):
    buf.append(line.rstrip())
    if len(buf) > 80:
        del buf[: len(buf) - 80]
    return "\n".join(buf)


def _note(log_buf, line, **progress):
    tail = _append_log(log_buf, line)
    progress["log_tail"] = tail
    if "detail" not in progress:
        progress["detail"] = line[:180]
    set_progress(**progress)


def _parse_line(line, current_step):
    """Return (step, percent, detail, kind) or None to keep previous.

    kind is a counter bucket so long phases can creep forward instead of sitting
    on one number. percent is a floor for that event; None means use the counter.
    """
    s = line.strip()
    if not s:
        return None
    if "Fetching" in s or s.startswith("Updating ") or "Fast-forward" in s:
        return ("pull", 6, s[:180], None)
    if "[spec]" in s:
        return ("spec", 12, s[:180], None)
    if s.startswith("[1/2]") or "Building with PyInstaller" in s:
        return ("pyinstaller", 16, "开始 PyInstaller", None)
    if "Analyzing " in s and ".py" in s:
        return ("pyinstaller", None, s[:180], "analyze")
    if "Processing standard module hook" in s:
        return ("pyinstaller", None, s[-120:], "hook")
    if "Building PYZ" in s:
        return ("pyinstaller", 52, "正在压缩 Python 模块", None)
    if "Building PKG" in s:
        return ("pyinstaller", 56, "正在打包引导程序", None)
    if "Building EXE" in s:
        return ("pyinstaller", 60, "正在生成 exe", None)
    if "Building COLLECT" in s:
        return ("pyinstaller", 66, "正在收集依赖和资源", None)
    if s.startswith("[2/2]"):
        return ("inno", 72, "PyInstaller 完成，开始 Inno", None)
    if s.startswith("Parsing [") or "Compiler engine version" in s:
        return ("inno", 74, s[:180], None)
    if s.startswith("Compressing:") or s.startswith("   Compressing:"):
        return ("inno", None, "正在压缩安装包文件", "inno_compress")
    if "Successful compile" in s:
        return ("inno", 92, s[:180], None)
    if "Build completed successfully" in s:
        return ("inno", 93, s[:180], None)
    if s.startswith("[ERROR]") or "RESULT=FAIL" in s:
        return (current_step, None, s[:180], None)
    return None


CREATE_NO_WINDOW = 0x08000000
_httpd = None


def _run(cmd, cwd, env, log_buf, step_hint):
    set_progress(step=step_hint[0], step_label=step_hint[1], percent=step_hint[2], detail=step_hint[1])
    proc = subprocess.Popen(
        cmd,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL,
        text=True,
        encoding="utf-8",
        errors="replace",
        creationflags=CREATE_NO_WINDOW,
    )
    n_analyze = 0
    n_hook = 0
    n_inno = 0
    pct_now = step_hint[2]
    current = step_hint[0]
    for raw in proc.stdout:
        line = raw.rstrip("\n")
        tail = _append_log(log_buf, line)
        parsed = _parse_line(line, current)
        extra = {"log_tail": tail}
        if parsed:
            current, pct, detail, kind = parsed
            extra["step"] = current
            extra["step_label"] = next((x[1] for x in STEPS if x[0] == current), detail)
            extra["detail"] = detail
            if kind == "analyze":
                n_analyze += 1
                pct = min(32, 16 + n_analyze // 5)
            elif kind == "hook":
                n_hook += 1
                pct = min(50, 32 + n_hook // 5)
            elif kind == "inno_compress":
                n_inno += 1
                extra["detail"] = "正在压缩安装包文件 (%s)" % n_inno
                pct = min(91, 74 + n_inno * 17 // 1800)
            if pct is not None and pct > pct_now:
                pct_now = pct
                extra["percent"] = pct_now
        set_progress(**extra)
    rc = proc.wait()
    return rc


def _pack_env():
    env = os.environ.copy()
    env["GOLGI_NOPAUSE"] = "1"
    env["GOLGI_FFMPEG"] = FFMPEG
    env["NO_PROXY"] = "*"
    env["no_proxy"] = "*"
    env["GIT_TERMINAL_PROMPT"] = "0"
    condabin = str(CONDA_ROOT / "condabin")
    scripts = str(CONDA_ROOT / "Scripts")
    env["PATH"] = condabin + ";" + scripts + ";" + str(CONDA_ROOT) + ";" + env.get("PATH", "")
    return env


def _read_kv(path: Path):
    data = {}
    if not path.is_file():
        return data
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip().upper()] = value.strip()
    return data


def _git_ssh_env(env):
    extra = env.copy()
    extra["GIT_TERMINAL_PROMPT"] = "0"
    extra["GIT_LFS_SKIP_SMUDGE"] = "1"
    if GIT_KEY.is_file():
        extra["GIT_SSH_COMMAND"] = (
            "ssh -i " + str(GIT_KEY) + " -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
        )
    if GIT_HELPER.is_file() and GIT_TOKEN.is_file():
        extra["GIT_CONFIG_COUNT"] = "2"
        extra["GIT_CONFIG_KEY_0"] = "credential.helper"
        extra["GIT_CONFIG_VALUE_0"] = ""
        extra["GIT_CONFIG_KEY_1"] = "credential.https://github.com.helper"
        extra["GIT_CONFIG_VALUE_1"] = "!" + str(GIT_HELPER)
    return extra


def _git_pull(env, log_buf):
    set_progress(step="pull", step_label="正在拉最新代码", percent=4, detail="git fetch " + BRANCH)
    if not (REPO / ".git").exists():
        set_progress(detail="客户端目录没有 git 仓库，跳过拉取，打当前目录")
        return True
    remotes = subprocess.run(
        ["git", "remote"], cwd=str(REPO), env=env, capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    if "origin" not in (remotes.stdout or ""):
        subprocess.run(
            ["git", "remote", "add", "origin", GIT_SSH_URL],
            cwd=str(REPO),
            env=env,
            capture_output=True,
            text=True,
        )
    extra_env = _git_ssh_env(env)
    rc = _run(["git", "fetch", "origin", BRANCH], REPO, extra_env, log_buf, ("pull", "正在拉最新代码", 6))
    if rc != 0 and GIT_TOKEN.is_file():
        set_progress(detail="SSH 部署密钥还没在 GitHub 生效，改用公司仓库只读 token", percent=6)
        rc = _run(
            ["git", "fetch", GIT_HTTPS_URL, BRANCH + ":refs/remotes/origin/" + BRANCH],
            REPO,
            extra_env,
            log_buf,
            ("pull", "正在拉最新代码", 7),
        )
    if rc != 0:
        set_progress(
            detail="GitHub 直连失败，尝试使用本机已同步过来的 origin/" + BRANCH,
            percent=7,
        )
    subprocess.run(["git", "checkout", BRANCH], cwd=str(REPO), env=env, capture_output=True)
    merge = subprocess.run(
        ["git", "merge", "--ff-only", "origin/" + BRANCH],
        cwd=str(REPO),
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if merge.returncode != 0 and rc != 0:
        set_progress(
            detail="拉代码失败（105 还没有这个公司仓库的只读权限），改为打当前目录里的代码",
            percent=8,
        )
        return True
    head = subprocess.run(
        ["git", "log", "-1", "--oneline"],
        cwd=str(REPO),
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    set_progress(commit=(head.stdout or "").strip(), percent=10, detail="代码已更新")
    return True


def _ensure_spec():
    set_progress(step="spec", step_label="正在准备打包 spec", percent=12, detail="检查 spec")
    ensure = CLIENT_PACK / "scripts" / "ensure_pack_spec.ps1"
    if ensure.is_file():
        subprocess.run(
            [
                "powershell",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ensure),
                str(REPO),
            ],
            capture_output=True,
        )
    spec = REPO / "Golgi_fNIRS_community.spec"
    tmpl = CLIENT_PACK / "templates" / "Golgi_fNIRS_community.spec"
    if not spec.is_file() and tmpl.is_file():
        shutil.copy2(tmpl, spec)
        set_progress(detail="已从模板拷入 Golgi_fNIRS_community.spec")
    return spec.is_file()


def _newest_installer():
    inst = REPO / "dist" / "installer"
    if not inst.is_dir():
        return None
    files = sorted(inst.glob("*_setup_*.exe"), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def _ensure_nas():
    for candidate in (NAS_DIR, NAS_DIR_IP):
        if candidate and os.path.isdir(candidate):
            return candidate
    kv = _read_kv(NAS_CRED)
    user = os.environ.get("PACK_NAS_USER") or kv.get("USER") or kv.get("USERNAME")
    password = os.environ.get("PACK_NAS_PASS") or kv.get("PASS") or kv.get("PASSWORD")
    if not user or not password:
        return None
    users = [user]
    if "@" not in user:
        users.append(user + "@golgi-bci.com")
    hosts = ("nas.golgi-bci.com", "192.168.0.89")
    share_name = "软件组共享"
    for host in hosts:
        share = r"\\%s\%s" % (host, share_name)
        subprocess.run(
            ["net", "use", share, "/delete", "/y"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    connected = False
    for host in hosts:
        share = r"\\%s\%s" % (host, share_name)
        for account in users:
            subprocess.run(
                ["cmdkey", "/add:" + host, "/user:" + account, "/pass:" + password],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            # SSH/network logon cannot persist cmdkey; net use with password still works.
            proc = subprocess.run(
                ["net", "use", share, password, "/user:" + account, "/persistent:yes"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            if proc.returncode == 0 or os.path.isdir(share):
                connected = True
                break
        if connected:
            break
    for candidate in (NAS_DIR, NAS_DIR_IP):
        if candidate and os.path.isdir(candidate):
            return candidate
    return None


def _upload(setup: Path, dry=False, log_buf=None):
    if log_buf is None:
        log_buf = []
    _note(
        log_buf,
        "[upload] 复制到本机 " + setup.name,
        step="upload",
        step_label="正在拷到输出目录",
        percent=94,
        installer=setup.name,
    )
    LOCAL_OUT.mkdir(parents=True, exist_ok=True)
    local_dest = LOCAL_OUT / setup.name
    shutil.copy2(str(setup), str(local_dest))
    _note(
        log_buf,
        "[upload] 已拷到本机 " + str(local_dest),
        local_path=str(local_dest),
        percent=96,
    )
    if dry:
        _note(
            log_buf,
            "[upload] dry-run，跳过 NAS",
            nas_path=None,
            percent=98,
        )
        return str(local_dest)
    nas_root = _ensure_nas()
    nas_dest = None
    if not nas_root:
        _note(
            log_buf,
            "[upload] NAS 还没登录，安装包只留在本机",
            nas_path=None,
            percent=97,
        )
        return str(local_dest)
    try:
        os.makedirs(nas_root, exist_ok=True)
        nas_dest = os.path.join(nas_root, setup.name)
        _note(
            log_buf,
            "[upload] 正在拷到 NAS " + nas_dest,
            percent=97,
        )
        shutil.copy2(str(setup), nas_dest)
        marker = os.path.join(
            nas_root,
            time.strftime("%Y%m%d %H%M%S") + " API pack " + setup.name.replace(".exe", "") + ".txt",
        )
        commit = snapshot().get("commit") or ""
        Path(marker).write_text(
            "branch: %s\ncommit: %s\ninstaller: %s\nsource: pack-api\n" % (BRANCH, commit, setup.name),
            encoding="utf-8",
        )
        _note(
            log_buf,
            "[upload] 已拷到 NAS " + nas_dest,
            nas_path=nas_dest,
            percent=99,
        )
    except Exception as e:
        _note(
            log_buf,
            "[upload] NAS 拷贝失败：" + str(e)[:160],
            nas_path=None,
            percent=97,
        )
    return nas_dest or str(local_dest)


def worker(dry=False, caller=None):
    log_buf = []
    env = _pack_env()
    try:
        set_progress(
            state="running",
            step="pull",
            step_label="正在拉最新代码",
            percent=2,
            detail="dry-run 开始" if dry else "开始",
            started_at=_now(),
            finished_at=None,
            installer=None,
            nas_path=None,
            local_path=None,
            error=None,
            log_tail="",
            dry=dry,
            caller=caller,
            changes=[],
            duration=None,
        )
        _git_pull(env, log_buf)
        set_progress(changes=_git_changes(snapshot().get("commit")))
        if not _ensure_spec():
            raise RuntimeError("缺少 Golgi_fNIRS_community.spec")
        bat = REPO / "build_and_pack.bat"
        if not bat.is_file():
            raise RuntimeError("找不到 build_and_pack.bat")
        rc = _run(
            ["cmd.exe", "/c", "echo.| call build_and_pack.bat"],
            REPO,
            env,
            log_buf,
            ("pyinstaller", "正在用 PyInstaller 打包程序", 18),
        )
        if rc != 0:
            raise RuntimeError("打包失败，退出码 %s" % rc)
        setup = _newest_installer()
        if setup is None:
            raise RuntimeError("没有生成 dist\\installer\\*_setup_*.exe")
        nas = _upload(setup, dry=dry, log_buf=log_buf)
        finished = _now()
        set_progress(
            state="success",
            step="done",
            step_label="完成",
            percent=100,
            detail="dry-run 完成，未传 NAS" if dry else "安装包已放到 NAS",
            finished_at=finished,
            duration=_duration_text(snapshot().get("started_at"), finished),
            installer=setup.name,
            nas_path=nas if not dry else None,
        )
        _add_history(_history_from_state())
    except Exception as e:
        finished = _now()
        set_progress(
            state="failed",
            step_label="失败",
            detail=str(e),
            error=str(e),
            finished_at=finished,
            duration=_duration_text(snapshot().get("started_at"), finished),
        )
        _add_history(_history_from_state())


def start_pack(dry=False, caller=None):
    with _lock:
        if _state["state"] == "running":
            return False, snapshot()
        _state["state"] = "running"
    t = threading.Thread(target=worker, kwargs={"dry": dry, "caller": caller}, daemon=True)
    t.start()
    return True, snapshot()


def request_shutdown():
    httpd = _httpd
    if httpd is None:
        return

    def _stop():
        time.sleep(0.15)
        httpd.shutdown()

    threading.Thread(target=_stop, daemon=True).start()


PAGE = r"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>社区筛查客户端打包</title>
<style>
  :root { color-scheme: light; }
  body { font-family: "Segoe UI", "Microsoft YaHei", sans-serif; margin: 0; background: #f4f6f8; color: #1f2933; }
  main { max-width: 720px; margin: 40px auto; background: #fff; padding: 28px 32px 36px; border-radius: 12px; box-shadow: 0 8px 24px rgba(15,23,42,.08); }
  h1 { font-size: 22px; margin: 0 0 8px; }
  .sub { color: #627d98; margin-bottom: 24px; }
  .pct { font-size: 56px; font-weight: 700; letter-spacing: -1px; }
  .step { font-size: 20px; margin: 4px 0 16px; }
  .bar { height: 14px; background: #e4e7eb; border-radius: 99px; overflow: hidden; }
  .bar > span { display: block; height: 100%; width: 0; background: #2563eb; transition: width .35s ease; }
  .bar.fail > span { background: #c0392b; }
  .bar.ok > span { background: #1f9d55; }
  .detail { margin: 16px 0 8px; color: #334e68; min-height: 1.4em; }
  .meta { font-size: 13px; color: #829ab1; line-height: 1.6; }
  button { margin-top: 20px; font-size: 16px; padding: 10px 22px; border: 0; border-radius: 8px; background: #2563eb; color: #fff; cursor: pointer; }
  button:disabled { background: #9fb3c8; cursor: not-allowed; }
  button.ghost { background: #fff; color: #334e68; border: 1px solid #cbd2d9; margin-left: 8px; }
  .on { display: inline-block; font-size: 13px; color: #1f9d55; background: #e3f9e5; padding: 4px 10px; border-radius: 99px; margin-bottom: 16px; }
  pre { background: #102a43; color: #d9e2ec; padding: 12px; border-radius: 8px; max-height: 220px; overflow: auto; font-size: 12px; }
  .hist { list-style: none; padding: 0; margin: 0 0 20px; display: flex; flex-direction: column; gap: 10px; }
  .hist li { font-size: 13px; color: #334e68; line-height: 1.5; background: #f8fafc; border: 1px solid #e4e7eb; border-radius: 10px; padding: 12px 14px; }
  .hist .ok { color: #1f9d55; font-weight: 600; }
  .hist .fail { color: #c0392b; font-weight: 600; }
  .hist .top { display: flex; flex-wrap: wrap; gap: 8px 12px; align-items: baseline; margin-bottom: 6px; }
  .hist .when { color: #102a43; font-weight: 600; }
  .hist .dur, .hist .who { color: #627d98; }
  .hist .chg { margin: 6px 0 0; padding-left: 18px; color: #334e68; }
  .hist .chg-title { margin-top: 8px; color: #627d98; }
</style>
</head>
<body>
<main>
  <h1>社区筛查客户端打包</h1>
  <div class="on" id="alive">服务在运行</div>
  <p class="sub">点「开始打包」会拉 develop2、打包并拷到 NAS。</p>
  <div class="pct" id="pct">0%</div>
  <div class="step" id="step">空闲</div>
  <div class="bar" id="bar"><span id="fill"></span></div>
  <p class="detail" id="detail">还没有开始打包</p>
  <p class="meta" id="meta"></p>
  <button id="btn" type="button">开始打包</button>
  <button id="off" class="ghost" type="button">关闭服务</button>
  <h3>最近的打包</h3>
  <ul class="hist" id="hist"></ul>
  <h3>本次日志</h3>
  <pre id="log"></pre>
</main>
<script>
async function refresh() {
  const r = await fetch('/api/status');
  const s = await r.json();
  const pct = s.percent || 0;
  document.getElementById('pct').textContent = pct + '%';
  document.getElementById('step').textContent = s.step_label || s.step || '';
  document.getElementById('detail').textContent = s.detail || '';
  document.getElementById('fill').style.width = pct + '%';
  const bar = document.getElementById('bar');
  bar.className = 'bar' + (s.state === 'failed' ? ' fail' : s.state === 'success' ? ' ok' : '');
  document.getElementById('btn').disabled = s.state === 'running';
  document.getElementById('btn').textContent = s.state === 'running' ? '正在打包…' : '开始打包';
  const off = document.getElementById('off');
  off.style.display = s.can_shutdown ? '' : 'none';
  off.disabled = s.state === 'running';
  const bits = [];
  if (s.can_shutdown && s.caller) bits.push('谁: ' + s.caller);
  if (s.commit) bits.push('代码: ' + s.commit);
  if (s.started_at) bits.push('开始: ' + s.started_at);
  if (s.finished_at) bits.push('结束: ' + s.finished_at);
  if (s.duration) bits.push('耗时: ' + s.duration);
  if (s.installer) bits.push('安装包: ' + s.installer);
  if (s.local_path) bits.push('本机: ' + s.local_path);
  if (s.nas_path) bits.push('NAS: ' + s.nas_path);
  if (s.error) bits.push('错误: ' + s.error);
  document.getElementById('meta').textContent = bits.join('  ·  ');
  document.getElementById('log').textContent = s.log_tail || '';
  const hist = document.getElementById('hist');
  const rows = s.history || [];
  function esc(t) {
    return String(t || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
  }
  hist.innerHTML = rows.length ? rows.map(h => {
    const ok = h.state === 'success';
    const st = ok ? '成功' : '失败';
    const packed = h.started_at || h.finished_at || '';
    const nas = h.dry ? '未传 NAS（测试）' : (h.nas_path ? '已拷 NAS' : (ok ? '未上 NAS' : ''));
    const chg = (h.changes || []).map(c => '<li>' + esc(c) + '</li>').join('');
    const who = (s.can_shutdown && h.caller) ? '<div class="who">谁：' + esc(h.caller) + '</div>' : '';
    return '<li><div class="top"><span class="' + (ok ? 'ok' : 'fail') + '">' + st + '</span>' +
      '<span class="when">打包时间 ' + esc(packed) + '</span>' +
      (h.duration ? '<span class="dur">耗时 ' + esc(h.duration) + '</span>' : '') +
      '</div>' + who +
      (h.installer ? '<div>' + esc(h.installer) + (nas ? ' · ' + nas : '') + '</div>' : '') +
      (chg ? '<div class="chg-title">这次改动</div><ul class="chg">' + chg + '</ul>' : (h.commit ? '<div>代码: ' + esc(h.commit) + '</div>' : '')) +
      (h.error ? '<div class="fail">' + esc(h.error) + '</div>' : '') +
      '</li>';
  }).join('') : '<li>还没有记录</li>';
}
document.getElementById('btn').onclick = async () => {
  await fetch('/api/pack', {method: 'POST'});
  refresh();
};
document.getElementById('off').onclick = async () => {
  if (!confirm('关闭后这个页面会打不开。再开请双击桌面上的「打开社区打包页」。')) return;
  await fetch('/api/shutdown', {method: 'POST'});
  document.getElementById('alive').textContent = '服务已关闭';
  document.getElementById('alive').style.color = '#627d98';
  document.getElementById('alive').style.background = '#e4e7eb';
};
refresh();
setInterval(refresh, 3000);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            body = PAGE.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/status":
            owner = _is_owner(self)
            st = snapshot()
            st["can_shutdown"] = owner
            if not owner:
                st["caller"] = None
                cleaned = []
                for item in st.get("history") or []:
                    row = dict(item)
                    row["caller"] = None
                    cleaned.append(row)
                st["history"] = cleaned
            self._json(200, st)
            return
        self.send_error(404)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/pack":
            q = parse_qs(urlparse(self.path).query)
            dry_raw = (q.get("dry") or q.get("dry_run") or [""])[0].lower()
            dry = dry_raw in ("1", "true", "yes")
            started, st = start_pack(dry=dry, caller=_caller_label(self))
            self._json(200, {"started": started, "status": st})
            return
        if path == "/api/shutdown":
            if not _is_owner(self):
                self._json(403, {"ok": False, "error": "只能在这台打包电脑上关闭服务"})
                return
            if snapshot().get("state") == "running":
                self._json(409, {"ok": False, "error": "正在打包，不能关服务"})
                return
            self._json(200, {"ok": True})
            request_shutdown()
            return
        self.send_error(404)

    def log_message(self, fmt, *args):
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        line = "[%s] %s\n" % (_now(), fmt % args)
        with open(LOG_DIR / "http.log", "a", encoding="utf-8") as f:
            f.write(line)


def main():
    global _httpd, _history
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    _history = _load_history()
    _httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print("pack-api http://0.0.0.0:%s  repo=%s" % (PORT, REPO))
    _httpd.serve_forever()


if __name__ == "__main__":
    main()
