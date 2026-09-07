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
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

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

_lock = threading.Lock()
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
        return dict(_state)


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


def _parse_line(line, current_step):
    """Return (step, percent, detail) or None to keep previous."""
    s = line.strip()
    if not s:
        return None
    if "Fetching" in s or s.startswith("Updating ") or "Fast-forward" in s:
        return ("pull", 6, s[:180])
    if "[spec]" in s:
        return ("spec", 12, s[:180])
    if s.startswith("[1/2]") or "Building with PyInstaller" in s:
        return ("pyinstaller", 18, "开始 PyInstaller")
    if "Analyzing " in s and ".py" in s:
        return ("pyinstaller", 28, s[:180])
    if "Processing standard module hook" in s:
        return ("pyinstaller", 40, s[-120:])
    if "Building PYZ" in s:
        return ("pyinstaller", 50, "正在压缩 Python 模块")
    if "Building EXE" in s:
        return ("pyinstaller", 58, "正在生成 exe")
    if "Building COLLECT" in s:
        return ("pyinstaller", 64, "正在收集依赖和资源")
    if "Build complete" in s or s.startswith("[2/2]"):
        return ("inno", 72, "PyInstaller 完成，开始 Inno")
    if s.startswith("Parsing [") or "Compiler engine version" in s:
        return ("inno", 74, s[:180])
    if s.startswith("Compressing:") or s.startswith("   Compressing:"):
        return ("inno", None, "正在压缩安装包文件")
    if "Successful compile" in s or "Build completed successfully" in s:
        return ("inno", 92, s[:180])
    if s.startswith("[ERROR]") or "RESULT=FAIL" in s:
        return (current_step, None, s[:180])
    return None


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
    )
    inno_compress = 0
    current = step_hint[0]
    for raw in proc.stdout:
        line = raw.rstrip("\n")
        tail = _append_log(log_buf, line)
        parsed = _parse_line(line, current)
        extra = {}
        if parsed:
            current, pct, detail = parsed
            extra["step"] = current
            extra["step_label"] = next((x[1] for x in STEPS if x[0] == current), detail)
            extra["detail"] = detail
            if current == "inno" and "压缩安装包" in (detail or ""):
                inno_compress += 1
                extra["percent"] = min(90, 74 + inno_compress // 40)
            elif pct is not None:
                extra["percent"] = pct
        extra["log_tail"] = tail
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


def _upload(setup: Path):
    set_progress(step="upload", step_label="正在拷到输出目录", percent=94, detail="复制 " + setup.name)
    LOCAL_OUT.mkdir(parents=True, exist_ok=True)
    local_dest = LOCAL_OUT / setup.name
    shutil.copy2(str(setup), str(local_dest))
    set_progress(local_path=str(local_dest), installer=setup.name, percent=96, detail="已拷到本机 " + str(local_dest))
    nas_root = _ensure_nas()
    nas_dest = None
    if not nas_root:
        set_progress(
            nas_path=None,
            percent=97,
            detail="本机已有安装包；NAS 还没登录（105 上缺少 nas.cred）",
        )
        return str(local_dest)
    try:
        os.makedirs(nas_root, exist_ok=True)
        nas_dest = os.path.join(nas_root, setup.name)
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
        set_progress(nas_path=nas_dest, percent=98, detail="已拷到 NAS")
    except Exception as e:
        set_progress(
            nas_path=None,
            percent=97,
            detail="本机已有安装包；NAS 拷贝失败：" + str(e)[:160],
        )
    return nas_dest or str(local_dest)


def worker():
    log_buf = []
    env = _pack_env()
    try:
        set_progress(
            state="running",
            step="pull",
            step_label="正在拉最新代码",
            percent=2,
            detail="开始",
            started_at=_now(),
            finished_at=None,
            installer=None,
            nas_path=None,
            local_path=None,
            error=None,
            log_tail="",
        )
        _git_pull(env, log_buf)
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
        nas = _upload(setup)
        set_progress(
            state="success",
            step="done",
            step_label="完成",
            percent=100,
            detail="安装包已放到 NAS",
            finished_at=_now(),
            installer=setup.name,
            nas_path=nas,
        )
    except Exception as e:
        set_progress(
            state="failed",
            step_label="失败",
            detail=str(e),
            error=str(e),
            finished_at=_now(),
        )


def start_pack():
    with _lock:
        if _state["state"] == "running":
            return False, snapshot()
        _state["state"] = "running"
    t = threading.Thread(target=worker, daemon=True)
    t.start()
    return True, snapshot()


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
  pre { background: #102a43; color: #d9e2ec; padding: 12px; border-radius: 8px; max-height: 220px; overflow: auto; font-size: 12px; }
</style>
</head>
<body>
<main>
  <h1>社区筛查客户端打包</h1>
  <p class="sub">点一下就会拉 develop2 最新代码、打包，并拷到 NAS。不用填参数。</p>
  <div class="pct" id="pct">0%</div>
  <div class="step" id="step">空闲</div>
  <div class="bar" id="bar"><span id="fill"></span></div>
  <p class="detail" id="detail">还没有开始打包</p>
  <p class="meta" id="meta"></p>
  <button id="btn" type="button">开始打包</button>
  <h3>最近日志</h3>
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
  const bits = [];
  if (s.commit) bits.push('代码: ' + s.commit);
  if (s.started_at) bits.push('开始: ' + s.started_at);
  if (s.finished_at) bits.push('结束: ' + s.finished_at);
  if (s.installer) bits.push('安装包: ' + s.installer);
  if (s.local_path) bits.push('本机: ' + s.local_path);
  if (s.nas_path) bits.push('NAS: ' + s.nas_path);
  if (s.error) bits.push('错误: ' + s.error);
  document.getElementById('meta').textContent = bits.join('  ·  ');
  document.getElementById('log').textContent = s.log_tail || '';
}
document.getElementById('btn').onclick = async () => {
  await fetch('/api/pack', {method: 'POST'});
  refresh();
};
refresh();
setInterval(refresh, 1000);
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
            self._json(200, snapshot())
            return
        self.send_error(404)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/pack":
            started, st = start_pack()
            self._json(200, {"started": started, "status": st})
            return
        self.send_error(404)

    def log_message(self, fmt, *args):
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        line = "[%s] %s\n" % (_now(), fmt % args)
        with open(LOG_DIR / "http.log", "a", encoding="utf-8") as f:
            f.write(line)


def main():
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print("pack-api http://0.0.0.0:%s  repo=%s" % (PORT, REPO))
    httpd.serve_forever()


if __name__ == "__main__":
    main()
