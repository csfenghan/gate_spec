# 个人约束示例 — ~/.gatespec/constraints.md
#
# 由 gatespec.specify / gatespec.plan 自动加载，优先级低于项目宪法和
# <repo>/.gatespec/constraints.md。有效结果只快照到 spec.md，不写入项目宪法；
# 特性级豁免必须获得用户明确批准；Test Control policy deviation 只能使用
# Requirements Constraint Basis 内的 TCE 机制。

## 文档语言

1. **Constraint Basis 正文使用中文。** 固定英文标题与字段名，以及路径、哈希、
   API 和代码标识符保持原样；更高优先级约束要求其他语言时，按优先级执行并记录冲突。

## 工程原则

2. **避免为契约违规、不可达错误路径或设计错误过度兜底。** 实现以调用方遵守已定义的 API 契约、
   调用顺序、前置条件及受控内部协议为前提；不要求违规操作继续成功、可恢复或获得兼容保证。
   不得为其引入收益不足以抵偿实现复杂度和人工理解成本的兼容、恢复、跨生命周期处理，或额外
   `class`、文件、接口、状态及抽象封装。低成本、局部且易理解的保护（如有效性检查、现有错误
   返回、断言或边界处 `try/catch`）可以采用或保留，使问题尽早明确失败而非静默掩盖。必要的
   内存、线程、资源安全与信任边界校验，以及契约要求处理的正常运行时失败，不得以本条为由省略；
   在满足这些底线后选择最简单的方案。
3. **测试控制必须完全隔离。** 优先使用现有业务契约、既有依赖注入或外部测试替身。
   只有当一个已命名验证缺口无法经生产契约可达时，才可以在原生任务阶段登记显式 Test Control。
   所有此类源文件必须位于以 `/src/testonly` 结尾的根下，并位于终端 `testonly`
   命名空间或模块中；不支持命名空间的语言使用前缀 `TestOnly` 或 `test_only`。正式产品
   API 不得因测试增加参数、选项、重载、getter 或状态。启用只能使用专用正向编译开关
   `*_ENABLE_TEST_HOOKS`，默认为 `OFF`，仅显式选择才为 `ON`；禁止运行时激活，也不得借用
   Debug、`BUILD_TESTING` 或其他通用开关。默认构建必须完全消除相关字段、分支、资源和符号。
   控制必须是强类型、声明式、单一目的和每实例 RAII，仅允许已命名的 one-shot、count、
   barrier、time、random、fault 或 observation 效果。禁止通用 callback、options bag、全局可变状态、
   校验绕过或业务算法副本。每个控制必须关闭一个具体验证缺口，不得预留占位，并须与最后一个
   消费者任务/测试同时删除。每个受影响的生产函数最多有一个视觉连续的专用宏 guard 块；
   块内只允许一次 `testonly` 调用，并将结果送回正常生产错误/结果路径。计数、等待、
   故障选择和 observer dispatch 必须全部位于 `/src/testonly`。
   项目 validator 必须从当前 clone 当次 configure/build/test 以及实际存在的 install/export/symbol
   输出重新枚举并计算每个 manifest、coverage 和 hit 值；禁止字面量/预计算哈希、只回显
   canonical row 或漏扫输出。所有登记路径必须是 slash-normalized 仓库相对路径，不得含前导
   `-`、空/`.`/`..` component、重复或尾随 `/`、空白或 shell metacharacter。
   上述 canonical policy 默认完整适用。只有 Requirements 阶段单独呈现并明确批准的高风险
   `R<n>` 决策，才可通过 Constraint Basis 的 TCE 表偏离一个 allowlisted Rule；不得在
   Design、Source、tasks、IA 或 review 阶段新增、扩大或推断豁免，也不得借 TCE 预登记具体
   TC、path::symbol、touchpoint、switch、wiring 或 validator。可偏离 Rule 仅限
   `source-root`、`language-marker`、`formal-api`、`switch-identifier`、`control-model`、
   `touchpoint-shape`、`validator-path-marker`，且必须提供替代的源码可辨识机制与后果。
   原生任务登记及 Closure/Audit/manifest/evidence/hash/clone wire/lifecycle、专用显式 opt-in
   且默认 OFF、禁止 runtime/umbrella、OFF 全消除、Bash 双 lane、相同 normal tests 加 ON
   consumers、当前 clone 实际输出重算且禁止 literal/echo、named gap、真实 consumer、无
   orphan 和随最后 consumer 移除，均为不可豁免底线。

## C++ 规范

4. **每个类独占一组文件。** 每个类分别使用自己的 `.h` 和 `.cpp`，不在同一源文件中实现多个类。
5. **遵循 Google C++ Style Guide。**

## 设计细化

6. **补充六项核心维度。** 设计须明确线程模型、内存/对象生命周期、关键模块与类、关键 API
   及其交互、外部接口行为，以及初始化/运行/销毁阶段的交互。
