# Codex 工程交接：Mac 旗舰中文输入法

状态：设计实施规格，不是已经上线的 Canonical；只用于未来独立项目。  
依赖：先读 REPORT.md 与 VALIDATION.md。本包不授权修改 PAIA、安装系统输入源、启用付费服务、公开部署或读取私人数据。

## 1. 要交付什么，不要交付什么

目标是独立、完整的原生中文输入法：普通输入准确稳定；明确个人词条与低成本纠错；个人原话的主动保存/调用；按需选文修改。PAIA 为默认关闭的扩展。

生产前端使用 Swift / AppKit / Core Text。网页 prototype.html 是视觉与行为样本，**不是**让你把 WebView 植入候选窗；engineering/core.js 的固定候选和 lease 是参考实现，**不是**拼音引擎或真实宿主事务实现。

不开发聊天中心、默认屏幕/剪贴板采集、自动发送、逐键云推理、私有键盘事件监听或未经同意的历史归档。性能与语义质量不因代码或测试数量增加而被视为完成。

## 2. 所有者和数据边界

| 模块 | 唯一职责 | 不得拥有 |
|---|---|---|
| IMEApp / InputController | IMKServer 生命周期、会话事件、合法宿主文本协议 | 网络、PAIA 内容数据库、任意跨应用查询 |
| InputSession | raw/caret/mode、会话代际、候选选择与唯一 commit dispatcher | provider 凭证、词典下载、后台正文日志 |
| EngineBridge | 版本受控 librime C API、内存释放、串行调用、值对象转换 | AppKit UI、异步模型重排后的偷偷改写 |
| CandidatePresentation | 原生面板、候选映射、视觉和无障碍 | 自己另造一次上屏、重新推断引擎候选索引 |
| PersonalLexicon | 明确词条、读音、受限统计、来源与不再学习 | 所有草稿/上下文的长期全文记录 |
| ExpressionStore | 用户确认的完整表达、修订、来源、删除 | 根据普通上屏自动创建“已发送”来源 |
| AssistCoordinator | 明确调用、单次范围、取消与结果失效 | 自动选择其他目标、自动转云、自动重试未知结果 |
| OptionalModelService | 本地模型装载/推理与资源回收 | 基础输入状态所有权、直接宿主写回 |
| OptionalPAIABridge | 精确能力、来源、撤回和合格结果传输 | 原始 PAIA IndexedDB 文件、越过现有权限的 Archive 回退 |
| PreferencesApp | 用户设置和相应操作入口 | 并发直接写正在使用的引擎用户库 |
| DictionaryBuilder / Updater | 下载验证、编译、idle 切换、回滚 | 组字中强制重启、绕过系统签名要求 |

在独立目录/仓库内实施，初始结构建议：

```text
Apps/
  NativeIME/              # IMKServer + AppKit 生命周期
  Preferences/            # 设置应用，普通 SwiftUI 可用
Packages/
  SessionCore/            # 纯状态、代际、效果、可回放
  EngineBridge/           # C ABI + librime adapter
  TextBoundary/           # UTF-8 / UTF-16 / grapheme，Client 能力
  CandidateUI/            # AppKit / Core Text，AX
  PersonalLexicon/
  ExpressionStore/
  AssistCoordinator/
Services/
  ModelService/           # 默认关闭
  PAIABroker/             # 默认关闭，无当前连接声明
Resources/
  Dictionaries/           # 每个文件的来源、许可、digest
Tools/
  BenchmarkCLI/
  DictionaryCompiler/
  PackageVerifier/
Tests/
  Session/ Engine/ TextBoundary/ NativeClient/ Compatibility/
  Privacy/ Lifetime/ ModelQuality/ InstallUpdate/
```

不是要求每个文件夹都成为单独进程或一个 PR。共享边界只有一个 writer；按用户任务集成，不再制造平行状态调度系统。

## 3. 值类型接口（语义规范，不是已编译 Swift API）

```swift
struct SessionKey: Hashable {
    let serverInstanceID: UUID
    let clientSessionID: UUID
}
struct EngineCandidateRef: Hashable {
    let session: SessionKey
    let targetEpoch: UInt64
    let inputGeneration: UInt64
    let dictionaryRevision: String
    let engineIndex: Int
    let rawSpanUTF8: Range<Int>
}
struct CandidateSnapshot {
    let session: SessionKey
    let targetEpoch: UInt64
    let inputGeneration: UInt64
    let privacyEpoch: UInt64
    let rawASCII: String
    let caretUTF8: Int
    let rows: [CandidateRow]       // ref + text + role + coverage
    let pageIndex: Int
    let hasMore: Bool
    let complete: Bool            // 不完整不能假装没有更多
}
struct CommitEffect {
    let operationID: UUID
    let session: SessionKey
    let targetEpoch: UInt64
    let inputGeneration: UInt64
    let text: String
    let replacementUTF16: NSRange?
    let origin: CommitOrigin      // engine / literal / explicitExpression / reviewedEdit
}
```

正式 CommitEffect **不包含 send 指令**。发送是宿主自己的行为，不通过一个布尔值“默认 false”保留未来偷偷开启的通道。网页核中的 `send:false` 仅为测试不变量。

不能把 UI 自己赋的 UUID 当作宿主提供的稳定文档身份；无法获得文档身份时，使用本次 IMK session 的受限生命周期，不承诺跨重建仍是同一文档。

EngineBridge 暴露 `startSession/processKey/readSnapshot/selectCandidate/consumeCommit/clearComposition/endSession` 等有限动作。select 必须验证 snapshot 当前性后，调用真实引擎选择；不可直接插入 candidate.text 绕过引擎。

## 4. 热路径与版本

启动时初始化兼容的只读词典；不要把首次编译、下载、数据库迁移或模型加载放进首个按键。库/API 版本、字典 revision、功能检测保存为无正文诊断。

每个 key 经过一个串行入口：验证当前 session → 处理模式/快捷键 → 引擎 process_key → 消费真实 commit → 生成 context 快照 → 原生文本与候选更新。任何给宿主的文本效果只在主线程/合法文本协议中发生。

librime API 返回的字符串/结构体要在释放前复制到值对象；调用对应 free API；session 销毁后不留悬空指针。API 前缀的 data_size 与函数存在性必须检查，不能依赖 master 比发行版本新的函数。

词库/设置变更先准备 staging；检查每套应发布方案有完整产物，再在没有活跃组字时切换。不是遇到一个 deploy=true 就假设所有方案成功。引擎层不得用高频磁盘扫描检查更新。

### 性能反例

“Task + timeout”不能安全终止卡住的 C++ 调用。基础引擎进程内路线必须通过尾延迟压力测试；失败则比较 XPC 独立基础引擎，但保留严格事件顺序、target binding 与未知结果处理。模型从开始就不进入按键线程。

基准报告要区分：单键 engine、context 复制、UI layout、宿主协议、可见呈现；P99 统计固定负载与样本数。只汇报最快一次或剔除失败按键不允许。

## 5. 组字和按键规则

完整表以 REPORT.md 第8节为准。关键不变量：

1. Space/数字只选择当时看到的候选映射；旧异步响应不能换数组。
2. Return 在组字中完成当次上屏并消费，不能同一次再作为发送键交给聊天框。
3. 没有组字时，Tab、方向、回车属于宿主。Command 组合不被输入法重定义。
4. Backspace/Forward Delete 修改原始输入或合法引擎确认段，不通过 CGEvent 模拟删除宿主已有文字。
5. 切换输入源、失焦与 commitComposition 只操作原来仍有效的 client；没有身份就拒绝跨目标效果。
6. 非本输入法产生的编辑、粘贴、撤销与宿主变更不能被当成本输入法已确认发送。

### 未上屏句内修正 G01

给定音节图、原始跨度和已确认左右段，对中间段加入约束重新解码。记录哪部分输入被覆盖；修改分词导致无合法路径时返回 `constraintConflict`，保留原始串和已确认段，让用户显式全句重算。

验收必须含：前/中/后段、同音字、分词改变、错拼插删、简拼、双拼、简繁输出、多码点字符和非常长后缀。仅拼接三个固定中文字符串不算 G01 完成。先尝试现有 API/策略能力；确实不够，再做最小引擎扩展，或与 libime 路线对照。

## 6. Client 能力等级，不虚构全系统原子写入

| 级别 | 可提供的功能 | 必要证据 |
|---|---|---|
| C0 | 基础组字/合法上屏 | 当前 IMK client 存在，标准协议可用 |
| C1 | 候选正确定位 | 当前 line rectangle 和屏幕坐标经过回读/可见验收 |
| C2 | 明确选区读取、局部上下文 | 实际范围、长度、截断与 Unicode 边界可靠；用户相应许可 |
| C3 | 审阅后的选区替换 | 当前 session/target、原文、选区、局部版本证据与失效机制可靠；宿主能力测试通过 |
| 不支持 C2/C3 | 手动选择/复制说明，基础输入保持可用 | 不请求额外广泛权限伪造“自动兼容” |

C3 仍不宣传“所有应用原子 compare-and-swap”。宿主可能在回读与提交间改变状态；需要严格范围及失败 readback。效果已发但回读不明，则 `uncertain`，不重复提交。对高风险宿主默认关闭高级替换。

默认上下文只使用本次自有组字。可选上下文先以例如前256/后128 UTF-16 units 的有界窗口验证；读取 actualRange，处理代理对与 grapheme 边界；不读取整个终端历史，也不靠截图补齐。

正式版本不知道浏览器是否无痕，不声称自动识别所有密码字段。可靠的安全输入状态优先，已知敏感应用/手动私密作为附加控制；没有状态不是允许全量学习的理由。

## 7. 个人词条与收藏的数据语义

手动词条：`termID, surface, reading, aliases, modeScope, explicitPin, createdAt, revision, deletedAt?`。
统计词条：`termID, cappedCount, lastUseBucket, learningPolicyEpoch, provenanceClass`，避免永久逐键时间线。
派生词条：额外保存来源引用/修订/许可代际，可按来源撤回，不复制来源整篇。

明确定义同形异音、同音异人、简繁以及领域冲突，不以词面当唯一身份。人工删除、不再学习、置顶与个人读音高于自动统计。批量重建/同步不能复活负向选择。

收藏表达：用户确认的完整文本、真实创建/保存时间、修订和来源类型。普通输入默认不生成收藏。手动 save 与已发送 message 有不同身份；没有真发送时间必须为 null，不用 savedAt 冒充。

恢复/导入只读取用户本次选择的文件。先预览范围与冲突，校验完整性、文本大小、编码与格式；拒绝任何隐含脚本。持续同步不属于本版默认主线。

## 8. AI 服务合同

每次任务 `requestID + targetLease + inputRevision + permissionEpoch + explicitAction + budget`。本地/云选项分开；端侧不可用不暗转云。取消、权限收紧、target销毁和原文/选区变化使响应失效。

输出只进入预览，不直接调用宿主。可结构校验数字、URL、代码和专有词；不能把这些校验称为语义完全保真。长期用户资料不默认塞入 prompt。

任何 provider call 都出现在独立服务的显式调用路径；所有输入/选词/翻页/设置/读取收藏与重渲染为零模型请求。失败/UNKNOWN 不自动重试；重试提示是新的可能付费调用。

本地模型候选应在实际任务上跑 A/B：轻量判别/重排与 n-gram、词库先比，之后才比较 0.5–3B 等生成模型。具体参数量不是产品承诺，必须符合基础机器、内存压力和中文质量。

## 9. PAIA 接口提案：未来授权后另开依赖

最新研究快照为 `6b4f96199e4f2de4040b1ed505a3610186b6815e` /0.43.4。开工必须重新读取主线/Canonical/在途writer，不能将此文档当成PAIA修改许可。

仅提议三类能力：`manualExpression.create`、`approvedExpression.query/read`、`approvedLexicon.delta`。这些名称是设计接口，不声称 PAIA 当前已导出同名能力。Archive 搜索、Context 读取和词汇抽取授权相互独立；旧 Context grant 不拓宽为 Archive。

Native Messaging 验证扩展ID与批准origin；broker / XPC校验客户端身份和请求权限。身份由信任边界获得，不能由请求体自报。禁止无认证 localhost、任意命令/文件路径、content script直接签发长期权限。

来源事件区分 `composition/commit/sendIntent/observedMessage/serverConfirmation/manualSaved`。自动归档沿用原PAIA Source owner，IME不发送第二份普通commit流水。去重用真实provider/message/branch/version，不用文本Hash代替事实身份。

## 10. 发布与许可证门槛

制作实际依赖 SBOM：repo/ref/file或package/digest/license/notice/source obligations/data provenance/更新通路。原作 MIT/BSD 不代表其内含所有词库或模型同许可。不得把GPL复制品改名成独立MIT原创。

基础路线优先独立前端 + librime；对照 Squirrel GPL Fork 的复用收益与维护成本，AIME模块只在清楚来源和兼容审查后采用。不要为了避开已读 GPL 源码就假装重写了同一表达；工程研究和实际复制界限必须可说明。

签名、公证、注册、更新、数据迁移、回滚、卸载必须成套验收。**不要运行 `install-dev.sh`、系统安装器、修改输入源偏好、取消系统安全保护或读取用户Profile，除非未来获得对应明确授权。** 开发阶段只在隔离目录运行合成宿主与CLITest。

## 11. 实施优先序与验收退出条件

### Batch A1：先打通真实文本与语言引擎

在新工作目录固定资源与许可证；建立可编译原生工程、纯SessionCore、真实C ABI桥和合成AppKit宿主。用实际引擎测raw→marked→candidate→commit及一次性效果；保留每次测试输入/库版本与有界日志。可以在不注册系统输入源的条件下完成部分证据，报告中标明。

退出条件：Unicode边界无已知失败；回退/数字选择不跳过引擎语义；无网络和隐式个人记录；相同字典的基准可复跑。结果只能称“原生引擎/宿主闭环”，不能称“系统IME已安装”。

### Batch A2：决定关键差异化是否成立

完成G01约束编辑与候选身份延迟竞争；采用现代强词库作同等对照；记录失败反例。不能仅用报告中的三段固定样例宣布整句修正完成。结果可能使我们改选引擎或者删除该增强，而不改变基本质量目标。

### Batch B：完整基础产品，不依赖AI

全拼/常用双拼、中英模式、标点、罕见字、用户词库、NativeUI、设置、更新和故障恢复。经另行授权的真正安装与兼容矩阵测试才能关闭系统IME门槛。

### Batch C：增强完整闭环

明确词条治理→精确原话收藏/调用→安全选文编辑。每层做消融；个人学习不是全量采集。真实AI、PAIA与语音分别有外部条件，不阻断已合格的本地产品，也不以Mock冒充完成。

### Batch D/E：旗舰准入

REPORT第15节的真实效率研究、兼容与长时试用、原生无障碍、发布/更新/卸载。按真实证据决定发布范围；遇到关键错窗/重复/隐私bug必须停止相关发布，不靠“所有单测通过”覆盖。

## 12. 验证证据格式

每次记录：源码SHA、资源SHA、版本/机器/OS、任务集来源与许可、初始学习状态、测试边界、完整结果、失败/跳过、限制。分开 `SIMULATED / ENGINE_NATIVE / APPKIT_HOST / INSTALLED_IME / LIVE_CLIENT / HUMAN_STUDY`。

原型的 308 项参考核检查、58 项网页检查不是这些类别的通用分母；其中分别有270几何组合和30页面布局组合。机器稳定结果与人感受到更好也不是同一件事。

工程时间估计与现金预算见REPORT第16节。不得为追赶时间静默缩小最终旗舰范围；可以依证据删除无净收益的增强。
