# sysapp-replacer

把上游开源应用重新打包成**系统包的身份**，并保证 data 分区安装能扛过重启。
每天定时检查上游 release，发现新版本就自动重打包、签名、发 Release。

## 替换映射

| 上游 | 原始包名 | 抢占的系统包名 | 特殊处理 |
|---|---|---|---|
| [BeiChen-CN/AppHarbor](https://github.com/BeiChen-CN/AppHarbor) | `com.app.market` | `com.xiaomi.market` | 移动 smali 类目录 + 改 Compose 资源目录 |
| [wxxsfxyzm/InstallerX-Revived](https://github.com/wxxsfxyzm/InstallerX-Revived) | `com.rosan.installer.x.revived` | `com.miui.packageinstaller` | **只改外层字符串**，类路径与 Shizuku/Dhizuku 依赖原样保留 |

## 为什么 versionCode 钉死 99999999

`PackageManagerService` 开机扫描系统包时，若 `/data/app` 里该包 versionCode **小于**系统分区上的版本，
判定为「系统应用已升级、data 版是旧残留」，直接删掉 data 版 → 退回原版。

所以要让「不装模块、纯覆盖安装」长期有效，data 版 versionCode 必须 **大于** 系统原版：

| 包 | 系统原版 versionCode |
|---|---|
| `com.miui.packageinstaller` | 55500 |
| `com.xiaomi.market`（MIUISuperMarket） | 远小于 99999999 |

代价：应用内「检查更新」会永远认为已是最新，升级只能靠本仓库的 Release。

## 工作流

`.github/workflows/build.yml`

- 触发：每天 03:00 UTC（11:00 CST）+ 手动 `workflow_dispatch`（可勾 `force` 重建）
- 每个应用独立 job，先解析上游最新 release（**包含 prerelease**，InstallerX 的 preview 就是 prerelease）
- 若 `appharbor-<tag>` / `installerx-<tag>` 这个 Release 已存在 → 跳过，不浪费构建时间
- 否则下载 APK → `scripts/repack.py` → 发布 Release + 上传 artifact

## 本机安装

```sh
mkdir -p ~/.config/sysapp-replacer
printf '%s' 'ghp_xxx' > ~/.config/sysapp-replacer/token
chmod 600 ~/.config/sysapp-replacer/token

./scripts/pull-install.sh              # 两个都更新
./scripts/pull-install.sh installerx   # 只更新一个
```

脚本会比对 `~/.cache/sysapp-replacer/state/<app>.tag`，同版本不重复安装。

### 定时自动安装（systemd user timer）

`~/.config/systemd/user/sysapp-replacer.{service,timer}` 每天 12:00 CST 跑一次：

```sh
systemctl --user status sysapp-replacer.timer
systemctl --user list-timers sysapp-replacer.timer
journalctl --user -u sysapp-replacer.service -n 30
```

手机没连（`adb get-state` 失败）时只下载不安装，下次连着会自动补装。
用户服务在**登出后不运行**；需要常驻的话 `sudo loginctl enable-linger jay`。

## 手动构建（本地）

```sh
curl -fsSL -o apktool.jar https://github.com/iBotPeaches/Apktool/releases/download/v3.0.3/apktool_3.0.3.jar
curl -fsSL -o uber-apk-signer.jar https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar

APKTOOL_JAR=./apktool.jar SIGNER_JAR=./uber-apk-signer.jar \
python3 scripts/repack.py \
  --apk upstream.apk \
  --old com.rosan.installer.x.revived \
  --new com.miui.packageinstaller \
  --version-code 99999999 \
  --out-dir dist
```

## 踩过的坑（写进脚本里了）

1. **apktool 的 build 缓存**：改完 `apktool.yml` 的 `versionInfo.versionCode` 直接 `b`，
   apktool 会打印 `AndroidManifest.xml and resources have not changed` 并**不写入新 versionCode**。
   必须先 `rm -rf src/build`。脚本里已强制清理并在构建后校验。
2. **Compose Multiplatform 资源路径**：`assets/composeResources/<pkg>.resources` 是按包名生成的目录，
   只改 smali 字符串不改目录名 → 启动即 `Missing resource with path` 崩溃。AppHarbor 必须 `--rename-assets`。
3. **InstallerX 不能全局替换**：它的 `applicationId` 是 `com.rosan.installer.x.revived`，
   但代码类在 `com.rosan.installer.*`；同时 `com.rosan.dhizuku.server.provider` 和 `moe.shizuku.*`
   是跨应用依赖，改了会断掉 Shizuku/Dhizuku 通信。所以只替换外层字符串、`--move-classes` 关闭。
4. **签名**：用 uber-apk-signer 的内置 debug key（固定），保证每次构建签名一致，覆盖安装不冲突。

## 回退

```sh
adb shell "pm uninstall-system-updates com.miui.packageinstaller"
adb shell "pm uninstall-system-updates com.xiaomi.market"
```
