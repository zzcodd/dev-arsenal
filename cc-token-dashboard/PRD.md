# CC Token Dashboard — PRD

> 一个常驻 macOS 菜单栏的 Claude Code token 用量实时仪表盘。
> 状态：**M0–M3 全部实现完成** v1.0 ｜ 负责人：Zhang Yu ｜ 日期：2026-06-15
> 构建运行见 [README.md](README.md)。`swift test` 7 项通过；CLI 与真实数据交叉校验通过。

---

## 1. 背景与目标

### 问题
日常用 Claude Code 时，对 token 消耗**没有直观概念** —— 不知道今天用了多少、哪个项目最费、离限流还有多远。

### 目标
做一个**常驻菜单栏的小工具**：
- 顶端用一个小标识 + 数字实时显示用量
- 点击展开一张设计精良的卡片，看到总量、趋势、分项目/分模型拆解
- 纯本地、零配置、隐私无忧

### 非目标（明确不做）
- 不做账单对账（订阅制下成本仅为"等价市价"参考，非实际扣费）
- 不做云端同步 / 多设备
- 不做对 Claude Code 行为的任何干预或拦截

---

## 2. 数据源与技术原理（已验证 ✅）

Claude Code 把每次会话以 JSONL 写到：
```
~/.claude/projects/<项目目录>/<session-uuid>.jsonl
```
每条 `type: "assistant"` 消息带一个 `message.usage` 字段：

| 字段 | 含义 | 计价档位 |
|---|---|---|
| `input_tokens` | 普通输入 | 标准 |
| `cache_creation_input_tokens` | 写缓存 | 约 1.25× 输入价（贵） |
| `cache_read_input_tokens` | 读缓存 | 约 0.1× 输入价（最便宜） |
| `output_tokens` | 输出 | 最贵 |

外加 `message.model`（如 `claude-opus-4-8`）、`timestamp`。

> **结论**：无需联网/API，纯本地文件解析即可。用 macOS 原生 **FSEvents** 监听目录，文件变更时**增量重算**，可做到秒级实时。原理同开源工具 `ccusage`，可行性已验证。

---

## 3. 功能范围（MoSCoW + 优先级）

### P0 — MVP（必须有，先跑起来）
1. **菜单栏常驻项**：显示「今日 token 总量」，如 `Today 2.4M`
2. **冷启动全量扫描**：读取 `~/.claude/projects/**/*.jsonl`，聚合历史用量
3. **实时增量更新**：FSEvents 监听，新消息写入后数字自动刷新
4. **展开卡片（点击 popover）**：
   - 今日总量（4 类 token 拆分）
   - 今日等价成本 $（按模型单价表估算）
   - 按项目 Top N 列表（二级分类）

### P1 — 体验增强
5. **时间维度切换**：今日 / 本周 / 全部
6. **按模型拆分**：Opus / Sonnet / Haiku 各自占比
7. **趋势图**：近 7 日柱状图（SwiftUI Charts）
8. **5 小时窗口进度**（如果能确定限流口径）：本窗口已用 X%

### P2 — 锦上添花
9. 开机自启动（LaunchAgent）
10. 阈值提醒（今日超过 N 推送通知）
11. 偏好设置：常驻指标可切换（今日量 / 成本 / 当前会话）
12. 浅/深色主题自适应

---

## 4. 信息架构与 UI

```
┌─ 菜单栏（常驻） ─────────────────────────┐
│  ◔ 2.4M                                  │   ← NSStatusItem，小图标+数字
└──────────────────────────────────────────┘
        │ 点击
        ▼
┌─ Popover 卡片 ───────────────────────────┐
│  Today                          ⚙︎  ✕    │
│  ┌────────────────────────────────────┐  │
│  │   2,412,033 tokens   ≈ $3.20       │  │  ← 主数字 + 等价成本
│  └────────────────────────────────────┘  │
│  Input 320K · Output 88K                 │  ← 4 类 token 拆分
│  Cache write 410K · Cache read 1.6M      │
│  ────────────────────────────────────    │
│  近 7 日  ▁▂▅▃█▆▂                          │  ← 趋势图（P1）
│  ────────────────────────────────────    │
│  By Project                              │  ← 二级分类（项目汇总）
│   ● cc-token-dashboard      1.2M  50%    │
│   ● mcp-repos               0.7M  29%    │
│   ● openclaw-study          0.5M  21%    │
│  ────────────────────────────────────    │
│  [Today ▾]              Updated 12:04:31  │  ← 时间维度切换 + 刷新时间
└──────────────────────────────────────────┘
```

设计基调：克制、留白、单一主数字突出；项目用颜色点区分；数字用等宽字体避免跳动。

---

## 5. 技术架构

**栈**：Swift / SwiftUI + AppKit（`NSStatusItem` + `NSPopover`），macOS 13+

分层：
```
┌─────────────────────────────────────────────┐
│ UI 层      SwiftUI Views（菜单栏文案 / Popover）│
├─────────────────────────────────────────────┤
│ 状态层     UsageStore (ObservableObject)       │  聚合结果、@Published 驱动 UI
├─────────────────────────────────────────────┤
│ 聚合层     Aggregator                          │  按 日/项目/模型 分组汇总
├─────────────────────────────────────────────┤
│ 解析层     JSONLParser（增量，记录文件 offset） │  只读新增行，避免全量重读
├─────────────────────────────────────────────┤
│ 监听层     FSEventsWatcher                     │  监听 ~/.claude/projects
├─────────────────────────────────────────────┤
│ 定价层     PricingTable（model → 单价）         │  静态表，估算 $
└─────────────────────────────────────────────┘
```

关键设计点：
- **增量解析**：每个 jsonl 文件记录已读 byte offset，FSEvents 触发后只读追加部分（JSONL 行追加写，天然适合）。
- **节流**：FSEvents 高频触发时做 debounce（如 500ms）再重算 UI。
- **"今日"边界**：按**本地时区**自然日切分（timestamp 是 UTC，需转换）。
- **项目名清洗**：目录名 `-Users-zhangyu-project-xxx` → 取末段做展示名。

---

## 6. 数据模型（草案）

```swift
struct UsageRecord {            // 单条 assistant 消息
    let timestamp: Date
    let project: String
    let model: String
    let input: Int
    let cacheCreation: Int
    let cacheRead: Int
    let output: Int
}

struct AggregatedUsage {        // 聚合结果
    let totalTokens: Int
    let byCategory: [String: Int]   // input/output/cacheW/cacheR
    let byProject: [String: Int]
    let byModel:   [String: Int]
    let estimatedCostUSD: Double
}
```

> 定价表初值需按官方核对（Opus/Sonnet/Haiku 四档 token 单价不同，缓存读取约为输入价 1/10）。先放占位值，标记 `// TODO: verify pricing`。

---

## 7. 任务拆解（里程碑）

### M0 — 数据管线打通（不带 UI，先证明能解析对）
- [ ] 命令行原型：扫描 `~/.claude/projects/**/*.jsonl`，打印今日总量
- [ ] 定义 `UsageRecord` / 解析逻辑，处理脏数据（缺字段、非 assistant 行）
- [ ] 与 `ccusage` 或手算交叉验证数字是否一致
- **验收**：终端能打出正确的今日 token 总量

### M1 — 菜单栏 MVP（P0 跑起来）
- [ ] 建 SwiftUI macOS App，`NSStatusItem` 常驻菜单栏
- [ ] 接入解析层，菜单栏显示「Today X」
- [ ] FSEvents 监听 + debounce，实时刷新
- [ ] `NSPopover` 展开卡片：主数字 + 4 类拆分 + 按项目 Top N
- **验收**：用 CC 时菜单栏数字会实时涨，点开能看到分项目

### M2 — 体验增强（P1）
- [ ] 时间维度切换（今日/本周/全部）
- [ ] 按模型拆分 + 等价成本 $
- [ ] 近 7 日趋势图（SwiftUI Charts）

### M3 — 打磨（P2）
- [ ] 开机自启动、阈值通知、偏好设置、主题适配
- [ ] 性能：大量历史文件下的冷启动耗时优化（offset 缓存落盘）

---

## 8. 关键风险 / 待定

| 项 | 风险 | 对策 |
|---|---|---|
| 定价准确性 | 官方单价会变，订阅制下"成本"仅为参考 | UI 上标注「≈ 等价市价」；单价集中到 PricingTable |
| 5 小时窗口口径 | 限流窗口规则未公开/会变 | P1 再做，拿不准就先不显示，避免误导 |
| 历史数据量大 | 冷启动全量解析慢 | offset 缓存 + 后台线程解析 + 先显示再补全 |
| JSONL 格式变更 | CC 升级可能改字段 | 解析层容错，缺字段记 0 不崩 |

---

## 9. ⚠️ 需要你自己真正消化的部分（别只靠 AI 代劳）

这几块是该自己理解的基础，建议亲手写一遍：
1. **FSEvents 的工作机制** —— 它是 macOS 文件系统事件，理解"事件不保证逐条、可能合并"，这关系到为什么要做 debounce + offset 增量。
2. **增量解析的 offset 管理** —— 文件被追加 vs 被重写（轮转）时 offset 失效的边界处理，是这类"监听日志"工具的通用难点。
3. **UTC→本地时区的日界切分** —— 简单但容易错，跨天统计 bug 多源于此。

这三点是工程通用能力（不只 iOS），对你后面做 Agent 工具链里的"监听/聚合本地状态"也复用得上。
