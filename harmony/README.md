# LocalSend for HarmonyOS NEXT（ArkTS 原生实现）

本目录是 `zhiqiuyan/localsend`（fork 自 [`localsend/localsend`](https://github.com/localsend/localsend)）中
`feat/harmonyos` 分支新增的**独立鸿蒙客户端工程**，使用 ArkTS + ArkUI 原生开发，不依赖 Flutter / Dart / Rust。

> **非官方客户端**。上游仓库采用 Apache-2.0 许可，本目录沿用该许可。
> 上游 `AGENTS.md` 明确限制 AI 生成的贡献；本工程只存在于个人 fork 中，**不会向上游提交 PR**，
> 仅把上游仓库当作协议与行为规范的参考源。

## 1. 为什么是独立实现

| 路线 | 结论 |
| --- | --- |
| 官方 Flutter 工程直接移植 | 上游是 Flutter 3.41.9 + Rust core（`packages/core`），HarmonyOS NEXT 无官方 Flutter 支持，需引入社区 `flutter_flutter` ohos 分支，且 `rustls` / `rhttp` / FRB 均需适配 |
| Flutter OHOS 社区移植（`Aloereed/localsend-ohos`） | 代码复用率最高，但社区 SDK 落后上游稳定版约 4 个月，且客户端与工具链绑定 |
| **ArkTS 原生重写（本工程）** | 工具链为本地 DevEco Studio 26.0，可直接编译 HAP、可上架 AppGallery；按公开的 LocalSend Protocol v2.2 实现，跨端互通性由协议保证 |

上游参考位置：

- 协议规范：[`localsend/protocol` v2.2](https://github.com/localsend/protocol)
- 路由定义：`packages/localsend_isolates/lib/api_route_builder.dart`
- 常量（端口 / 多播组 / 版本）：`packages/localsend_isolates/lib/constants.dart`
- 服务端行为：`packages/core/src/http/server/v2.rs`、`AGENTS.md` 的 Networking / Multicast 章节
- 社区 ArkTS 参考：`azhu003/localsend-harmony`（仅 HTTP，2025-11 后停更）

## 2. 协议实现对照（v2.2）

| 能力 | 端点 / 机制 | 本工程状态 |
| --- | --- | --- |
| UDP 多播发现 | `224.0.0.167:53317`，`announce: true` | 已实现，周期 5 s，TTL 2 |
| 单播注册（多播的应答方式） | `POST /api/localsend/v2/register` | 已实现（收到 `announce=true` 时单播回复） |
| 设备信息（调试） | `GET /api/localsend/v2/info` | 已实现 |
| 传输协商 | `POST /prepare-upload`，`?pin=` | 已实现，含 400 / 401 / 403 / 409 / 204 |
| 文件上传 | `POST /upload?sessionId&fileId&token` | 已实现，含 token / IP 绑定与 SHA-256 校验（不符返回 422） |
| 取消会话 | `POST /cancel?sessionId` | 已实现 |
| 反向传输 | `POST /prepare-download`、`GET /download`、`GET /` | 已实现（链接分享，按协议使用明文 HTTP） |
| 内部端点 | `POST /show` | 已实现（返回 200） |
| 单会话约束 | 同一时刻仅一个 upload session | 已实现，含 10 分钟过期兜底 |
| v1 端点 | `/api/localsend/v1/*` | 不提供（与上游 Rust core 一致） |
| v3 协议 | `localsend/protocol` 的 `v3`（2026-07 新增） | 未实现，当前官方客户端主线仍为 v2 |
| HTTPS / mTLS / 证书 pinning | 上游强制双向证书 | **未实现**，见第 5 节 |

协议字段、路径、状态码与 [v2.2 规范](https://github.com/localsend/protocol) 保持一致；
`version` 固定为 `2.2`，`deviceType` 为 `mobile`，`protocol` 为 `http`。

## 3. 目录结构

```
harmony/
├── AppScope/                         # 应用级配置与资源
├── build-profile.json5               # 产品 / 模块 / SDK 版本
├── oh-package.json5                  # 工程依赖（当前为零三方依赖）
├── hvigor/                           # 构建器配置
├── entry/
│   ├── src/main/module.json5         # 权限：INTERNET、GET_WIFI_INFO
│   └── src/main/ets/
│       ├── entryability/             # UIAbility 生命周期
│       ├── pages/Index.ets           # ArkUI 界面（发送 / 记录 / 设置）
│       ├── common/                   # 常量、模型、日志、偏好设置、Context
│       ├── util/                     # 字节工具、SHA-256、文件读写
│       ├── protocol/
│       │   ├── HttpCodec.ets         # 轻量 HTTP/1.1 解析与响应构造
│       │   ├── MulticastDiscovery.ets
│       │   ├── LocalSendServer.ets   # TCPSocketServer 上的接收端
│       │   ├── LocalSendClient.ets   # 系统 HTTP 客户端上的发送端
│       │   ├── SessionManager.ets
│       │   └── Routes.ets
│       └── service/LocalSendService.ets  # 门面：发现、收发、状态与 UI 事件
```

HarmonyOS 未提供 HTTP **服务端** Kit，因此接收端基于 `socket.TCPSocketServer` + 自研
`HttpCodec`（解析请求行、头部、`Content-Length` 正文；不支持 chunked）。
发送端使用系统 `http` 模块，避免重复实现客户端协议栈。

## 4. 构建与运行

环境：DevEco Studio 5.0+（本仓库在 26.0.0.865 / SDK API 26 上开发），
`compatibleSdkVersion` 声明为 `5.0.0(12)`，最低支持 HarmonyOS NEXT 5.0 / API 12。

> **路径限制（重要）**：hvigor 会校验工程绝对路径，仅允许 ASCII 字母、数字、
> `-_.()`、空格与 `@`。若仓库克隆在含中文的路径下（例如 `D:\文档\...`），
> 构建会报 `00306003 Specification Limit Violation: Invalid project path`。
> 请把 `harmony/` 复制到纯 ASCII 目录（如 `D:\localsend-harmony`）后再构建；
> 修改源码后同步回仓库目录即可提交。此限制来自构建工具，与代码无关。

1. 用 DevEco Studio 打开 `harmony/` 目录（路径需满足上述 ASCII 约束）。
2. `File > Project Structure > Project > Signing Configs`，勾选 **Automatically generate signature**
   登录华为开发者账号后自动生成调试签名；命令行构建需先完成此步骤。
3. `File > Sync and Refresh Project`（或在 `harmony/` 下执行 `ohpm install`）。
4. 连接 HarmonyOS NEXT 真机，`Run > Run 'entry'` 生成并安装 HAP。
5. 在**双方设备**上关闭加密：官方客户端「设置 → 网络 → 加密」取消勾选；
   本客户端默认即为 HTTP 模式。

命令行构建（Git Bash，使用 DevEco 内置工具链；`java` 必须来自 DevEco 的 JBR，
否则 `PackageHap` 会报 `spawn java ENOENT`）：

```bash
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
export JAVA_HOME="C:/Program Files/Huawei/DevEco Studio/jbr"
export PATH=".../jbr/bin:.../tools/node:.../tools/ohpm/bin:.../tools/hvigor/bin:$PATH"

cd harmony
ohpm install
hvigorw --mode module -p product=default assembleHap --no-daemon
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`（未配置签名时）
或 `entry-default-signed.hap`（配置签名后，可安装到真机）。

**本机验证结果（2026-11-06，DevEco Studio 26.0.0.865 / SDK API 26）**：
`ohpm install` 通过；`CompileArkTS` 通过；`PackageHap` 通过；
`BUILD SUCCESSFUL`（33 tasks），生成 352 KiB 的 `entry-default-unsigned.hap`。
唯一警告为 `No signingConfig found for product default`（未签名，属预期），
另有一批 `Function may throw exceptions` 静态检查提示（异步 API 未逐层声明 throws，不影响产物）。
真机联调、签名安装与多播互通仍未在本机验证，需在 HarmonyOS NEXT 设备上完成。

真机多播验证要点：两台设备接入同一 Wi-Fi、关闭路由器 AP 隔离、
允许 TCP/UDP 53317 入站；首次运行需授予网络权限。

## 5. 已知限制与后续路线

**当前限制（MVP）**

1. **仅 HTTP，无 TLS。** 官方客户端默认启用 HTTPS 并强制双向证书认证，
   peer 身份为客户端证书 DER 的 SHA-256 大写十六进制。与官方客户端互通时，
   **必须在双方关闭加密**。这是当前最重要的功能边界。
2. 单次上传整包缓冲在内存，上限 64 MiB；超过返回 413。大文件需改为流式落盘。
3. 未实现 IPv6 多播扩展（`ff12::fd3a:e420`）、HTTP legacy 子网扫描、
   证书 pinning / 设备收藏、后台长时保活、桌面卡片与分享扩展。
4. 接收端单连接单请求（`Connection: close`），未实现 keep-alive 与并发 /upload 的流水线复用。
5. 未在真机上联调：多播组加入、系统 HTTP 客户端对局域网明文请求的策略、
   DevEco 签名流程均需在设备上复核。

**HTTPS 迁移路径（可行，本地 SDK 已具备能力）**

- 服务端：`socket.constructTLSSocketServerInstance()` + `TLSConnectOptions`，
  证书 / 私钥由 `TLSSecureOptions.cert` / `.key` 加载；
  `TLSSecureOptions.isBidirectionalAuthentication` 可开启双向认证。
- 客户端：`socket.constructTLSSocketInstance()` + `skipRemoteValidation`（自签证书场景）。
- 证书：需生成设备级自签 X.509 证书并持久化（`cryptoFramework` 可生成密钥，
  X.509 编码需自行实现或引入 native 库），fingerprint 改为证书 DER 的 SHA-256。
- 完成后 `protocol` 字段改为 `https`，即可与官方默认配置互通。

**其它后续项**：Protocol v3、WebRTC 传输、流式上传、应用内文件预览、上架 AppGallery。

## 6. 与上游同步

本分支保留了 `upstream` 远端：

```bash
git remote -v                       # origin = fork, upstream = localsend/localsend
git fetch upstream
git merge upstream/main             # 在 feat/harmonyos 上合并上游变更
```

`harmony/` 为新增目录，与上游 `app/`、`packages/` 等路径无重叠，正常合并不会产生冲突。
上游协议升级时，对照 `packages/core/src/http/server/v2.rs` 与
`localsend/protocol` 更新 `Routes.ets` / `Models.ets` / `LocalSendServer.ets`。
