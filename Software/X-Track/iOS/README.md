# X-TRACK iOS 26

X-TRACK 码表的 iOS 26 移植版。原 240×240 LVGL 界面**原样保留**（与硬件版共用同一份 `USER/App` 代码、LVGL v8.3 和 `lv_conf.h`，16 位色深），放大居中显示在 iPhone 屏幕上。

## 功能对应

| 原硬件 | iOS |
| --- | --- |
| 旋转编码器 旋转（上下滑动/切换焦点/缩放地图） | **相机控制按钮 (Camera Control)**：轻按后左右滑动，每一档 = 编码器一格 |
| 旋转编码器 按下 / 长按 | 相机控制按钮 完全按下 / 按住 |
| 触摸 | 触摸屏（与模拟器相同） |
| GPS (ATGM336H) | CoreLocation（支持锁屏后台继续记录轨迹） |
| IMU 计步 / 地磁 | CoreMotion（CMPedometer、加速度计、陀螺仪、磁力计） |
| 电池 | UIDevice 电量 / 充电状态 |
| 蜂鸣器 | AVAudioEngine 方波（跟随静音开关） |
| SD 卡 | App 的「文稿」目录（可在「文件」App 中访问） |

### 相机控制按钮说明

* 需要带相机控制按钮的 iPhone（iPhone 16 系列及以后）。
* iOS 只在 App 运行相机会话时才把相机控制按钮事件交给第三方 App，所以前台运行时会开启一个最低分辨率、不保存任何画面的相机会话，状态栏会出现绿色相机指示点。首次启动需允许相机权限。
* 系统的按键事件接口同时会接管音量键（音量键也等于“按下”）。
* 「设置 › X-TRACK」中可关闭相机控制按钮或反转滑动方向。

## 地图与轨迹

* 将地图瓦片（`TilesConverterForLVGL` 生成的 `.bin`，与硬件版相同）放入：`文件 › 我的 iPhone › X-TRACK › MAP/<level>/<x>/<y>.bin`
* 记录的轨迹保存在 `Track/TRK_*.gpx`，设置保存在 `SystemSave.json`。

## 编译

需要 macOS + Xcode 26 + [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```sh
brew install xcodegen
cd Software/X-Track/iOS
./build_ipa.sh            # 生成 build/X-TRACK-unsigned.ipa（未签名）
# 或: xcodegen generate && open XTrack.xcodeproj
```

GitHub Actions（`.github/workflows/ios-ipa.yml`）在每次推送后自动编译，并把未签名 IPA 上传为构建产物 `X-TRACK-iOS26-unsigned-ipa`。

未签名 IPA 需要自行签名后安装（如 Sideloadly / AltStore / 自己的开发者证书，或 TrollStore）。

## 代码结构

```
iOS/
├── project.yml              XcodeGen 工程描述
├── build_ipa.sh             打包未签名 IPA
└── XTrack/
    ├── Core/                可移植 C/C++：LVGL 显示/输入/文件系统接入、iOS HAL
    │   ├── XTCore.{h,cpp}
    │   ├── HAL_iOS.cpp
    │   └── lv_fs_ios.{h,c}
    ├── Platform/            Objective-C++：界面、传感器、声音、相机控制按钮
    │   ├── XTViewController.mm
    │   ├── XTCameraControl.mm   (AVCaptureIndexPicker + AVCaptureEventInteraction → 编码器)
    │   ├── XTSensors.mm
    │   └── XTTone.mm
    └── Resources/           Info.plist、图标、Settings.bundle
```
