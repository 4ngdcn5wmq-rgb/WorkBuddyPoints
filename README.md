# WorkBuddyPoints · WorkBuddy 每日签到领积分 iOS App

一个纯本地运行的 iOS App：填一次凭据，之后每天自动完成 WorkBuddy「Buddy 加油站」签到、领取积分，并顺带完成派猫猫旅行闭环。

- **凭据只存本机 Keychain**，签名 IPA 里不含任何账号信息
- **三层执行保障**：BGAppRefreshTask 后台任务 + 本地通知提醒 + 打开 App 自动补跑
- **精确到分的定时**：内置 App Intents，可配「快捷指令」个人自动化
- 无需 Mac 也能拿到 IPA：仓库自带 GitHub Actions 云编译流水线

## 1. 快速开始

| 你的情况 | 路线 |
|---|---|
| 没有 Mac，只有 Windows/手机 | **第 4.2 节**：GitHub Actions 云端编译，全程网页操作 |
| 有 Mac | `make ipa`（详见第 4.1 节） |
| 已有自签软件（AltStore / Sideloadly / 爱思助手等） | 拿到未签名 IPA 后直接喂给自签软件（见第 5 节） |

> 未签名 IPA 就是自签软件的标准输入，工程产出的正是这种文件。

## 2. App 功能

**仪表盘**
- 今日签到状态（已完成 / 待领取）、连续天数、每日可得、积分余额
- 派猫猫旅行：状态、当前地点、预计到达时间、今日派遣余量
- 「立即签到领积分」手动触发完整闭环
- 最近一次执行结果摘要

**记录**
- 全部执行历史（来源：手动 / 打开 App / 后台任务 / 快捷指令），最多保留 300 条

**设置**
- 三种凭据模式：长效令牌（推荐）/ Bearer 令牌 / 网页 Cookie（需回放原始 User-Agent）
- 智能粘贴识别：授权码（`WBAUTH1:` 开头）、客户端登录态 JSON、JWT、Cookie 串、长效令牌，粘贴进来自动识别填充
- 测试连接（只查状态、不领取）
- 每日自动执行开关 + 执行时间 + 旅行开关 + 通知开关

**每日闭环逻辑**
1. 解析凭据（长效令牌模式会先向插件网关刷新接口令牌，并保存轮换结果实现自续期）
2. 查询今日签到状态 → 未签则领取（接口幂等，重复执行不会重复发积分）
3. 旅行闭环：`arrived` 先领奖励 → `idle` 且未达每日上限则派出 Buddy
4. 结果写进历史记录，按设置发本地通知

## 3. 凭据从哪来（三选一）

| 模式 | 来源 | 说明 |
|---|---|---|
| 长效令牌（推荐） | PC 客户端登录态 / 本机 `~/.workbuddy` 下的凭据文件 | App 自行刷新续期，客户端不开也能签 |
| Bearer 令牌 | 客户端登录态里的 `accessToken`（JWT，`eyJ` 开头） | 有效期较短，过期需重填 |
| 网页 Cookie | 在已登录的网页端用开发者工具复制 Cookie | 网关把会话与 User-Agent 绑定，必须同时填当时的 UA |

默认接口域名 `www.codebuddy.cn`、旅行域名 `www.workbuddy.cn`，一般不用改；如登录态里带有别的 `domain`，以它为准（可在设置里修改）。

## 4. 拿到 IPA

### 4.1 有 Mac（一条命令）

```bash
# 需要 Xcode；生成图标需 python3 -m pip install Pillow
make ipa
# 产物：build/WorkBuddyPoints-unsigned.ipa
```

只想看代码：`make open` 会生成并打开 Xcode 工程。

### 4.2 没有 Mac：GitHub Actions 云端编译（免费，全程网页操作）

工程已内置工作流 `.github/workflows/build-ipa.yml`，在 GitHub 的 macOS 云编译机上编译。**公开仓库完全免费**（macOS 分钟对公开仓库不计费）。

**第 1 步：注册 GitHub（已有账号跳过）**
1. 打开 <https://github.com> → 右上角 **Sign up**
2. 邮箱注册 → 验证邮箱 → 选 **Free** 方案

**第 2 步：新建仓库**
1. 登录后点右上角 **「+」→ New repository**
2. Repository name 填 `WorkBuddyPoints`
3. 务必选 **Public**（Actions 才免费；代码里没有任何密钥，公开无风险）
4. 不要勾 "Add a README" → 点绿色 **Create repository**

**第 3 步：上传工程文件（关键一步）**
1. 本机解压 `WorkBuddyPoints.zip`，**双击进入** `WorkBuddyPoints` 文件夹
2. 文件夹里按 `Ctrl + A` **全选里面的所有内容**（能看到 `scripts`、`.github`、`WorkBuddyPoints`、`README.md`、`Makefile` 等）

   > 选的是「文件夹里的东西」，不是文件夹本身；`.github` 是隐藏文件夹，`Ctrl + A` 会一起选中，正常现象
3. GitHub 仓库页面点 **Add file → Upload files**
4. 把选中的所有文件**直接拖进网页虚线框**，等上传完
5. 点 **Commit changes**，等十几秒

**第 4 步：运行工作流**
1. 仓库顶部菜单点 **Actions**
2. 首次进入提示 workflows 被禁用 → 点绿色 **「I understand my workflows, enable them」**
3. 左侧点 **Build Unsigned IPA** → 右侧 **Run workflow** → 分支确认 `main` → 再点绿色 **Run workflow**
4. 刷新页面，出现黄色「编译未签名 IPA」运行记录，点进去看实时日志

**第 5 步：下载 IPA**
1. 约 3~6 分钟变绿勾 ✓ 后，回到仓库首页
2. 根目录会多出 `ipa` 文件夹 → 里面的 `WorkBuddyPoints-unsigned.ipa` → 点 **Download** 保存

（Artifacts 页面也有同名产物，保留 90 天。）

**常见问题**

| 现象 | 原因 / 解决 |
|---|---|
| Actions 里没有 Build Unsigned IPA | 第 3 步漏传了 `.github` 隐藏文件夹。补救：Add file → Create new file，文件名填 `.github/workflows/build-ipa.yml`，把仓库里同名文件内容粘进去提交 |
| Run workflow 按钮是灰的 | 仓库不是 Public（私有仓库也可跑，但免费额度有限），或分支不对 |
| 编译失败红叉 | 点进运行记录看日志；多为上传时文件结构不对（应保证仓库根目录直接有 `scripts/`、`WorkBuddyPoints/`） |
| 下载的 ipa 是 0 KB | 工作流没跑完就下载了，等绿勾 |

## 5. 签名安装（喂给自签软件）

拿到 `WorkBuddyPoints-unsigned.ipa` 后任选其一：

- **Sideloadly（Windows/macOS）**：手机连电脑 → 拖入 ipa → 输入 Apple ID → Start。7 天后过期，覆盖安装续期
- **AltStore（Windows/macOS）**：装 AltServer → 手机装 AltStore → 通过它安装 ipa；电脑开着时自动后台续签
- **爱思助手（Windows）**：工具箱 → 自签/IPA 签名 → 导入 ipa + Apple ID → 签名安装
- **iOS App Signer** 等其他工具同理

**注意**
- 免费 Apple ID 签名有效期 **7 天**，到期用同一 Apple ID 覆盖安装即可；**覆盖安装不会丢 Keychain 里已保存的凭据**
- 首次安装后若提示「不受信任的开发者」：设置 → 通用 → VPN 与设备管理 → 信任你的 Apple ID
- 同一免费 Apple ID 同时最多 3 个自签 App

## 6. 自动执行的三层保障与诚实的局限

| 层 | 机制 | 可靠性 |
|---|---|---|
| 1 | BGAppRefreshTask 后台刷新 | 系统择机执行，大概率每天跑到，但 iOS 不保证精确时间 |
| 2 | 本地通知定时提醒 | 到点提醒打开 App；点开即自动补跑（App 检测到今天没成功就跑） |
| 3 | 快捷指令个人自动化 | **精确到分**且免开 App：快捷指令 → 自动化 → 每天 HH:MM 运行「WorkBuddy 每日签到」意图 |

后台刷新偶尔被系统跳过属于 iOS 正常行为；把第 3 层配上就等于每天准点执行。所有接口均幂等，多跑也不会重复发积分。

## 7. 项目结构

```
WorkBuddyPoints/
├── .github/workflows/build-ipa.yml   # 云端编译流水线（未签名 IPA）
├── scripts/
│   ├── gen_xcode_project.py          # 生成 .xcodeproj（不依赖 macOS，含结构自校验）
│   ├── build-ipa.sh                  # macOS 上一键编译打包
│   └── make_icon.py                  # 生成 App 图标
├── WorkBuddyPoints/
│   ├── WorkBuddyPointsApp.swift      # 入口 + 前后台调度
│   ├── AppDelegate.swift
│   ├── Info.plist / *.entitlements
│   ├── Assets.xcassets/              # 图标
│   ├── Models/                       # Credential / Snapshots / HistoryEntry
│   ├── Services/                     # APIClient / CheckinEngine / CredentialStore / HistoryStore / NotificationService / KeychainStore
│   ├── Background/                   # BackgroundTaskManager（BGAppRefreshTask）
│   ├── Intents/                      # 快捷指令意图（签到 / 查积分）
│   ├── UI/                           # 仪表盘 / 记录 / 设置
│   └── Utilities/                    # 格式化 / 智能粘贴解析
├── Makefile
└── README.md
```

## 8. 常用命令

```bash
python3 scripts/gen_xcode_project.py    # 生成/更新 Xcode 工程（Windows/Linux 也能跑）
python3 scripts/gen_xcode_project.py --check
python3 scripts/make_icon.py            # 重新生成图标
make ipa                                # macOS：出未签名 IPA
```

## 9. FAQ

**Q：为什么不能直接给一个签名好的 ipa？**
签名必须用 Apple 签发的证书，而证书和你的 Apple ID 绑定；任何人替你签都需要你的证书私钥，不安全也不可行。所以标准做法是：工程产出**未签名 IPA**，你用自己的 Apple ID 自签（免费、7 天、可无限续）。

**Q：凭据安全吗？**
凭据只写进本机 iOS Keychain（`ThisDeviceOnly`，不进 iCloud 备份同步），网络请求只发往 WorkBuddy / 腾讯官方接口域名。清除凭据在「设置 → 清除本机凭据」。

**Q：换了手机 / 重装 App 后凭据还在吗？**
Keychain 数据随卸载清除（未开启 iCloud 钥匙串同步），重装后重新粘贴一次即可，智能粘贴框能自动识别。

**Q：会连续签到中断吗？**
漏签一天连续天数就重置。建议把「快捷指令个人自动化」配上（第 6 节第 3 层），基本不会漏。

**Q：旅行接口报「no active buddy」？**
说明账号尚未在客户端激活派猫猫旅行，先在 WorkBuddy 客户端里玩一次旅行即可，不影响签到。
