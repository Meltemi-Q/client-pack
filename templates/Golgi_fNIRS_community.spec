# -*- mode: python ; coding: utf-8 -*-
import os
import shutil
from PyInstaller.utils.hooks import collect_all

datas = [
    ('bgkd.png', '.'),
    ('gorky.png', '.'),
    ('VERSION.txt', '.'),
    ('GreenTek_v4.json', '.'),
    ('valid_channel.json', '.'),
    ('SimSun.ttf', '.'),
    ('SimHei.ttf', '.'),
    ('fnirs_app\\config\\defaults.toml', 'fnirs_app\\config'),
    ('vendor\\fnirs-report-generator\\generate_report.py', 'vendor\\fnirs-report-generator'),
    ('vendor\\fnirs-report-generator\\config', 'vendor\\fnirs-report-generator\\config'),
    ('vendor\\fnirs-report-generator\\cases', 'vendor\\fnirs-report-generator\\cases'),
    ('vendor\\fnirs-report-generator\\source_repos\\bci_rehab\\src\\assets\\brain_no_bg.png', 'vendor\\fnirs-report-generator\\source_repos\\bci_rehab\\src\\assets'),
    ('addfiles\\audio_pool_template\\fixed',    'audio_pool\\fixed'),
    ('addfiles\\audio_pool_template\\say_word', 'audio_pool\\say_word'),
    ('addfiles\\audio_pool_template\\dichotic', 'audio_pool\\dichotic'),
]
binaries = []
def _real_ffmpeg_path():
    candidates = [
        os.environ.get('GOLGI_FFMPEG', ''),
        os.path.expanduser(r'~\scoop\apps\ffmpeg\current\bin\ffmpeg.exe'),
        os.path.expandvars(r'%LOCALAPPDATA%\Programs\ffmpeg\bin\ffmpeg.exe'),
        shutil.which('ffmpeg') or '',
        os.path.expanduser(r'~\scoop\shims\ffmpeg.exe'),
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            try:
                if os.name == 'nt' and os.path.getsize(path) < 1000000:
                    continue
            except OSError:
                continue
            return path
    return ''

ffmpeg_path = _real_ffmpeg_path()
if ffmpeg_path and os.path.isfile(ffmpeg_path):
    binaries.append((ffmpeg_path, '.'))

hiddenimports = [
    'numpy',
    'numpy.core._multiarray_tests',
    'scipy.signal',
    'scipy.interpolate',
    'scipy.io',
    'scipy.ndimage',
    'scipy.spatial',
    'matplotlib.pyplot',
    'PySide6.QtWidgets',
    'PySide6.QtCore',
    'PySide6.QtGui',
    'PySide6.QtSvg',
    'PySide6.QtTest',
    'PySide6.QtMultimedia',
    'pyqtgraph.exporters',
    'pyqtgraph.graphicsItems',
    'serial.tools.list_ports',
    'fnirs_app.processing.channel_position_style',
    'fnirs_app.ui.widgets.test_flow2_page',
    'fnirs_app.ui.widgets.paradigm_select_dialog',
    'fnirs_app.paradigms.nback_controller',
    'fnirs_app.paradigms.nback_content',
    'tools.SignalQualityIndex',
    'reportlab',
    'tomli',
    'pywt',
    'pyaudio',
    'fitz',
    'h5py',
    'qrcode',
    'qrcode.image.pil',
    'edge_tts',
    'viztracer',
]
tmp_ret = collect_all('PIL')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret_reportlab = collect_all('reportlab')
datas += tmp_ret_reportlab[0]; binaries += tmp_ret_reportlab[1]; hiddenimports += tmp_ret_reportlab[2]

tmp_ret_edge_tts = collect_all('edge_tts')
datas += tmp_ret_edge_tts[0]; binaries += tmp_ret_edge_tts[1]; hiddenimports += tmp_ret_edge_tts[2]

try:
    tmp_ret2 = collect_all('viztracer')
    datas += tmp_ret2[0]; binaries += tmp_ret2[1]; hiddenimports += tmp_ret2[2]
except Exception:
    pass

try:
    tmp_ret_qr = collect_all('qrcode')
    datas += tmp_ret_qr[0]; binaries += tmp_ret_qr[1]; hiddenimports += tmp_ret_qr[2]
except Exception:
    pass


a = Analysis(
    ['geerji_fnirs_new.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Golgi_fNIRS_community',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=[os.environ.get('GOLGI_APP_ICO') or 'gorky.ico']
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Golgi_fNIRS_community',
)
