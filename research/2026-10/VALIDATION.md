# 验证记录与证据边界

## 最终交付中已经执行的验证

| 对象 | 结果 | 实际范围 |
|---|---|---|
| Mac 原生 AppKit / IMK 编译探针 | 31 / 31 | 原生自建文本宿主，不是注册输入源或跨应用 |
| 真实 librime 基线 | 24 人工样本 × 8轮，2,240键；p99 0.492541 ms | process_key/context复制；不含UI/系统事件延迟 |
| 三词字典消融 | 3个目标首选修正，21个对照首选不变 | 明确提供答案后的机制实验，不是一般准确率 |
| FoundationModels 可用性 | 返回 unavailable(deviceNotEligible) | 只查询状态，没有生成/付费或原因诊断 |
| JavaScript 参考状态核 | 308 / 308 | 38个行为/边界检查 + 270个合成几何组合 |
| Chromium 网页交互 | 58 / 58 | 28个行为/运行检查 + 30个尺寸/主题/面板组合；不是原生IME |
| 网页网络与异常 | 测试期间请求0、页面运行错误0 | 本页面事件观测；不证明整台机器无网络 |

原型最终源码 SHA、实际执行时间和 Chromium 版本见 `evidence/ui-results.json`；状态核见 `evidence/core-results.json`。测试所有输入为人工资料。网页中没有真实拼音引擎、模型或 PAIA 客户端。

## 没有完成，不能隐含宣称完成

微信/搜狗/苹果的同数据集真实准确率横评；最新RimeIce/万象方案基准；注册输入源后的真实IMK跨应用输入；原生候选窗物理点击和全屏/多屏定位；原生VoiceOver；真正的句内约束解码；长期学习；实际本地模型/中文ASR质量和电池；真实外部PAIA连接/付费；人群盲测和长期留存。

这不影响报告提出旗舰设计，但决定了不能宣称“产品已经比成熟输入法更好”。

## 保留的修订和失败

1. 原生引擎最初人工夹具有三处拼音或简拼与目标不一致，已审查修正并以新用户目录重跑。v0原文件、纠正说明仍保留在Mac；最终统计只采用v1，未将旧失败改成成功。
2. 网页最初整套测试失败：重复 `set_content` 留在同一JavaScript realm导致顶层常量重声明；测试还未显式展开折叠实验控件。另发现面板先显示、下一帧才定位导致聚焦时滚动和遮挡。分别修复测试隔离/真实控件展开与生产原型定位顺序，没有放松断言或用force click掩盖。
3. 后续有3个测试因Playwright字符串 `wait_for_function` 遇到原型CSP禁止unsafe-eval而失败。改为等待真实可见的enabled按钮，**没有放宽CSP**；其余55项已通过的断言不删。
4. 审查额外修复：超出原型raw预算时清除旧候选，保留原输入；关闭修改面板清理 `data-result`；替换后的完整正文受总大小预算限制，不能只限制替换片段。

记录：`ui-results-initial-failed.json`、`ui-output-second-failed.txt`、`ui-progress-second-failed.json`、`ui-results-csp-harness-failed.json` 保留失败经过。最终通过记录为 `ui-results.json`，不是选择旧的通过记录代替新源验证。

网页保留“固定演示”标注；全部历史与修改结果为本页人工样例。只保证本页例子的原文完整插入、选区失效检查、取消和无网络，不把这些变成跨进程安全认证。

## 复跑

环境要求：Node.js，Python3+Playwright，以及已安装的Chromium。这里没有依赖自动下载步骤。

```bash
node engineering/test-core.cjs
python3 engineering/build-prototype.py
python3 engineering/test-ui.py
```

当前脚本使用 `/usr/bin/chromium`；其他机器将该路径改为本机实际浏览器路径，单独记录版本。测试使用新 `about:blank` 文档后 `set_content`，没有访问真实网站。

Mac原生复跑：`bash native/run-appkit-probe.sh`。源码副本的SHA与原Mac一致；该脚本仅新建临时目录、编译并运行，不注册或启用输入源。原始 librime 实验资料的收集方式见 `native/README.md`。

## 当前资源与规格没有混同

目标数据集3,000条、百万事件回放、500小时使用、24人交叉试验、目标延迟/内存均是未来方案，**不是本轮已通过的数值**。原型中512字符/200k文本预算是样机防护，不是正式输入法不可更改的设计上限。原生观察摘要文件不冒充逐字节原始回执。
