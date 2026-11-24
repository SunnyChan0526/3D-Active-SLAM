# Jetson 主機端設定（相機相關）

這些設定在**主機**（JetPack 6.2／Ubuntu 22.04）上做，不在容器裡。是 2026-11-24 在 AGX Orin 上讓 D435i 穩定時找到的；換到 Orin NX 時要重做一次。

```bash
bash setup/jetson_host_setup.sh            # 只檢查，不改任何東西
bash setup/jetson_host_setup.sh --apply    # 套用 1、2（第 2 項需要 sudo）
```

`[todo]` 表示還沒設好，`[ok]` 表示已設好。套用後把相機拔掉重插，再跑一次檢查。

## 1. PipeWire 關掉 v4l2 監控
- **現象**：PipeWire 的 media-session 會把 D435i 當成 v4l2 視訊裝置打開，IMU、color 串流起不來。
- **做法**：把 `/usr/share/pipewire/media-session.d/media-session.conf` 複製到 `~/.config/pipewire/media-session.d/media-session.conf`（使用者設定會整份取代系統設定），把 `session.modules.default` 裡的 `v4l2` 註解掉，再重啟 `pipewire`、`pipewire-media-session`。
- 修改前的檔案會備份成 `media-session.conf.bak.<時間>`。
- 這是**使用者**設定，換帳號要重做。
- 如果系統用的是 wireplumber 而不是 pipewire-media-session，腳本不會處理，要另外手動關掉它的 v4l2 monitor。

## 2. USB autosuspend
- **現象**：AGX 上原本是手動執行 `echo -1 > /sys/module/usbcore/parameters/autosuspend`，重開機就會還原。
- **做法**（兩層，重開機後仍有效）：
  - systemd 服務 `activeslam-usb-autosuspend.service`：開機時寫入 `-1`，等於把原本的手動設定變成持久設定。
  - udev 規則 `/etc/udev/rules.d/99-activeslam-usb-power.rules`：Intel（`8086`）USB 裝置一接上就設 `power/control=on`。開機時相機可能比上面的服務更早被偵測到，所以要多這一層。
- **移除**：`sudo systemctl disable --now activeslam-usb-autosuspend`，再刪掉 udev 規則和 `/etc/systemd/system/activeslam-usb-autosuspend.service`。

## 3. uvcvideo（只檢查，不改）
- AGX 上試過卸載 `uvcvideo`，**效果未證實**。我們用 librealsense 的 RSUSB 後端（libusb），理論上不需要 uvcvideo。
- 腳本只回報它是否載入。若在 NX 上懷疑它造成問題，可以手動試 `sudo modprobe -r uvcvideo`，並把結果記錄下來。

## 檢查時也會看
- 板子型號、L4T 版本、電源模式（`nvpmodel -q`）。
- RealSense 是否以 USB 3.x（≥ 5000 Mb/s）連線，以及 `power/control` 的值。

## 不在這支腳本裡的 Jetson 設定
- `docker/run.sh` 內的 Jetson 預設值：`ACTIVESLAM_COLOR_FPS=15`、`ACTIVESLAM_CAMERA_ALIGN=false`、`ACTIVESLAM_RVIZ_PREFIX="nice -n 19"`、`ACTIVESLAM_VINS_TRACK_USED_ONLY=1`。
- RealSense udev 權限規則：`setup/99-realsense-libusb.rules`（見 `docker/README.md`）。
