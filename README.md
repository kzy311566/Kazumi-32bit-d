# Kazumi Android 32-bit 镜像仓库

本仓库自动跟踪上游 [Predidit/Kazumi](https://github.com/Predidit/Kazumi) 的 release，
并在其源码上叠加一小组补丁，构建 **Android 32 位（`armeabi-v7a`）APK**。

> [!NOTE]
> 本仓库不是官方仓库，只提供 **Android 32 位兼容版本**。
> 原项目版权、代码与维护归上游作者及贡献者所有。如需完整功能，也可直接使用
> [上游官方版本](https://github.com/Predidit/Kazumi/releases)。

## 为什么需要补丁：弹幕曾经完全不可用

上游把弹弹play 的 API 凭证做成**编译期常量**，由它私有的 GitHub Actions secrets 注入：

```dart
// 上游 lib/utils/dandan_credentials.dart
const Map<String, String> dandanCredentials = {
  'id': String.fromEnvironment('DANDANAPI_APPID'),
  'value': String.fromEnvironment('DANDANAPI_KEY'),
};
```

```yaml
# 上游 .github/workflows/release.yaml
flutter build apk --split-per-abi \
  --dart-define=DANDANAPI_APPID=$DANDANAPI_APPID \
  --dart-define=DANDANAPI_KEY=$DANDANAPI_KEY
```

本仓库无法读取上游的 secrets。而原先的构建命令是裸的 `flutter build apk --split-per-abi`，
一个 `--dart-define` 都没有，于是 `AppId` 与 `AppSecret` 都变成空字符串，
签名成了 `base64(sha256("" + ts + path + ""))`。

实测结论（弹弹play 开放弹幕网络对**所有**接口都要求鉴权）：

| 请求 | 结果 |
| --- | --- |
| 不带鉴权头 | `403 Missing Authentication Headers` |
| 空凭证（原 32 位包的实际行为） | `403 Missing Authentication Headers` |
| 正确凭证 | `200` + 正常弹幕数据 |

这就是"弹幕功能缺失"的真正原因——**不是没有 API，而是凭证没被编译进去**。
上游的接口、签名算法、弹幕渲染都是好的，实测
`/api/v2/bangumi/bgmtv/302286` → `bangumiId 15449` →
`/api/v2/comment/154490001` 能返回 3767 条弹幕。

## 本仓库的补丁做了什么

| 文件 | 作用 |
| --- | --- |
| `patches/01-credentials-and-gating.patch` | 凭证改为运行时可解析；无凭证时跳过请求并给出明确原因，而不是发一个必然 403 的签名 |
| `patches/02-settings-and-startup.patch` | 新增凭证设置项与启动时加载 |
| `overlay/lib/utils/dandan_credentials.dart` | 含占位符的凭证模块，构建时被注入真实值 |
| `overlay/lib/services/storage/danmaku_credential_store.dart` | 持久化用户自己填写的凭证 |
| `overlay/lib/pages/settings/danmaku/danmaku_credential_tile.dart` | 设置 → 弹幕设置 → **弹幕接口凭证** |
| `scripts/inject-credentials.mjs` | 把仓库 secrets 写进上面的占位符 |
| `scripts/validate-credentials.mjs` | 构建前用真实凭证调一次 API，凭证错了直接失败 |
| `scripts/verify-apk.sh` | 校验产物确实是纯 `armeabi-v7a`，且含 libmpv |

补充修复：

- **无镜像凭证时自动降级**：`KAZUMI_APPID` / `KAZUMI_KEY`（`api.kazumi.fyi` 番剧镜像）
  与弹弹play 是**两套不同**的凭证。缺前者时镜像接口必然失败，现在会自动回退到
  ECH 直连，而不是一直报错。
- **集号越界防御**：弹幕库的集号约定是 `bangumiId * 10000 + 集数`，集数最多 4 位。
  超出时现在会跳过并记录日志，而不是拼出一个错误 ID。

## 配置（必读）

在本仓库 **Settings → Secrets and variables → Actions** 中添加：

| Secret | 说明 |
| --- | --- |
| `DANDANAPI_APPID` | 弹弹play 开放平台 AppId |
| `DANDANAPI_KEY` | 弹弹play 开放平台 AppSecret |
| `KAZUMI_APPID` | （可选）Kazumi 番剧镜像 AppId，没有则留空，会自动走 ECH |
| `KAZUMI_KEY` | （可选）Kazumi 番剧镜像 AppSecret |

凭证申请：<https://dev.dandanplay.com>

> [!WARNING]
> 凭证是**编译期注入**的。任何拿到 APK 的人都能从包里提取出 AppSecret
> （上游官方版也一样）。如果这不可接受，请把 secrets 留空，
> 让用户在 App 内填写自己的凭证——补丁会优先使用用户填写的那份。

## 关于签名密钥

上游的 `android/app/build.gradle` 用 **debug 密钥**签名 release 包，CI 每次运行都会
重新生成 debug keystore。后果是：**同一个应用、同一个版本号，两次构建的签名不同，
无法覆盖安装**，只能先卸载（会丢数据）。

workflow 里已经加了可选的固定签名。配置以下 secrets 后，构建会改用你自己的
keystore，从第二个版本起就能正常覆盖安装：

| Secret | 说明 |
| --- | --- |
| `SIGNING_KEY_BASE64` | keystore（`.jks`）文件的 base64，例如 `base64 -w0 release.jks` |
| `KEY_ALIAS` | keystore 里的 key 别名 |
| `KEY_STORE_PASSWORD` | keystore 密码 |
| `KEY_PASSWORD` | key 密码（通常与上面相同） |

不配置也能构建，只是会退回 debug 签名并给出警告。

## 构建

`push` 到 `main`、手动 `workflow_dispatch`、或每 12 小时的定时任务都会触发。
在 Actions 页面手动触发时可以：

- `force`：即使该版本 Release 已存在也重新构建并覆盖
- `upstream_tag`：指定要构建的上游 tag（默认取最新 release）

> [!NOTE]
> 若目标版本的 Release 已存在，且触发方式是 `push` 或定时任务，构建会**跳过**
> （避免重复烧构建时长）。要重新构建同一版本，请手动触发并勾选 `force`。

构建流程会依次：checkout 本仓库 → 解析上游 tag → **git clone 上游源码（不是 tarball）**
→ 覆盖 `overlay/` → `git apply --3way patches/` → 逐条反向校验补丁确实落地 →
配置签名 → **用真实凭证调一次 API 确认弹幕可用** → 构建 armeabi-v7a APK →
校验是纯 32 位且含 libmpv → 发布 APK + `checksums.txt`，release 说明由构建脚本生成
（内含 AppId、密钥哈希、APK sha256）。

其中"用真实凭证调一次 API"这步很关键：凭证填错会在构建阶段直接失败，
而不是发布一个弹幕静默失效的包。实际已实测通过：19 个单测全绿、
`Credentials accepted. Danmaku will work in the built APK.`。

## 下载

请前往本仓库的 [Releases](https://github.com/kzy311566/Kazumi-32bit-d/releases) 页面。

## 维护说明

### 补丁基线（重要）

`patches/*.patch` 是对着 **`upstream-tag` 文件里记录的那个上游 tag** 生成的整体 diff，
所以一定能干净应用到该 tag。workflow 默认构建上游**最新 release**；
若最新 tag 与基线不同，构建会用 `git apply --3way` 做三方合并并在日志里给出警告。
`--3way` 需要 base blob，因此 workflow 用 **git clone** 而不是 tarball。

早期版本这里犯过一个真实错误：补丁是对着上游 `main` 分支生成的，而 workflow 构建的是
最新 release tag，两棵树内容不同，导致**每个补丁都静默失败**，任务卡在
"Confirm the patch set landed"。所以现在：

- `upstream-tag` 是唯一的事实来源
- `tools/verify-all.mjs` 也用同一个 tag 校验，和 CI 一致
- `git apply` 失败会**直接让构建失败**，不会产出坏包

### 升级到新的上游版本

```bash
# 1. 取到目标 tag
git -C upstream fetch --depth 1 origin refs/tags/<newtag>:refs/tags/<newtag>

# 2. 在干净工作树上重建补丁
git -C upstream worktree add --detach ../.tag <newtag>
#    把改动移植进 ../.tag（可先用 git apply --3way 应用旧补丁，再人工核对）

# 3. 重新生成补丁并更新基线
git -C ../.tag diff HEAD --output=patches/01-credentials-and-gating.patch -- <files...>
#    ...02、03 同理
#    然后修改 upstream-tag 文件

# 4. 校验
node tools/verify-all.mjs
```

### 本地校验

改动补丁后，建议先在本地跑一遍不需要 Flutter 的校验（工作区根目录执行）：

```bash
# 全量校验：workflow 结构、换行符、占位符、凭证注入两条路径、
# 真实 API 凭证、补丁能否干净应用到基线 tag、gradle 签名改写
node tools/verify-all.mjs

# 只跑离线检查（跳过真实 API 调用）
node tools/verify-all.mjs --offline

# 端到端复现弹幕链路，确认接口和 ID 约定仍然成立
node tools/verify_chain.mjs 302286 1
```

其中 `tools/verify_chain.mjs` 会在没有设备的情况下验证
`bgm id → dandan bangumiId → episodeId → 弹幕条数` 这条链路。

重新生成补丁的方式：在干净的 upstream 工作树里修改文件，然后

```bash
git diff --output=patches/XX-name.patch -- <files...>
```

注意必须用 `git diff --output=`，不要用 shell 重定向：后者在 Windows 上会写入
CRLF，导致 Linux runner 上 `git apply` 失败。

## 声明

原项目版权、代码与维护归属于上游项目作者及贡献者。
本仓库仅为社区兼容性构建与分发用途。
