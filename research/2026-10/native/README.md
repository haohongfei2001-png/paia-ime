# 原生验证文件

`NativeProbe.swift`、`ModelAvailabilityProbe.swift` 和 `model-availability.txt` 从本轮 Mac 原文件重新读取，容器副本 SHA-256 与原始记录一致。可使用 `bash run-appkit-probe.sh` 在 Mac 的新临时目录复跑 AppKit 检查；该脚本不注册输入源、不打开安装器。

`evidence/native-observation-summary.json` 是依据已执行工具回执制作的**观察摘要**，不冒充完整原始 JSON。原始 librime 基线/补词脚本、全部候选和最初失败夹具保留在授权 Mac：

`/tmp/mac-ime-research-20261009-mPkcSY`

`collect-original-evidence.py NEW_DESTINATION` 只复制本实验明确列出的12个源码/结果文件，核验已经记录的哈希；不复制安装包、模型、词库、私人Profile或任何PAIA文件，不覆盖已有目录。临时目录若被系统清理，脚本拒绝，不猜测其他来源。

Squirrel 1.1.2 发行包仅在 Mac 上解包以执行实验，未安装。包 SHA-256：
`614746013212937623d5bbab9901e9c43d1ec937aa32307d6b6092a05e308287`。
本交付不重新分发该二进制或词库。原始脚本中的schema/版本/配置见复制所得文件；重跑应使用新的隔离工作目录，不让前一次用户词频或编译结果污染实验。

FoundationModels 探针只查可用性，无生成请求。`deviceNotEligible` 是这次返回值，不能根据该字符串单独判定原因。
