# 领域文档（Domain Docs）

工程技能在探索本代码库时应如何消费本仓库的领域文档。

## 开始探索之前，先读这些

- **`GLOSSARY.md`**（仓库根目录），或
- **`GLOSSARY-MAP.md`**（仓库根目录，如果存在）：它指向每个上下文各自的 `GLOSSARY.md`。读与当前主题相关的每一个。
- **`docs/adr/`**：读与你即将改动的领域相关的 ADR。多上下文仓库还要看 `src/<context>/docs/adr/` 里上下文级决策。

如果这些文件不存在，**静默继续**。不要指出它们的缺失，也不要主动建议创建。`/domain-modeling` 技能（经由 `/grill-with-docs` 和 `/improve-codebase-architecture` 触达）会在术语或决策真正被敲定时惰性创建它们。

## 文件结构

单上下文仓库（大多数仓库）：

```
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

多上下文仓库（根目录存在 `GLOSSARY-MAP.md`）：

```
/
├── GLOSSARY-MAP.md
├── docs/adr/                          ← 系统级决策
└── src/
    ├── ordering/
    │   ├── GLOSSARY.md
    │   └── docs/adr/                  ← 上下文级决策
    └── billing/
        ├── GLOSSARY.md
        └── docs/adr/
```

## 使用术语表中的词汇

当你的输出要提到某个领域概念时（issue 标题、重构提案、假设、测试名里），使用 `GLOSSARY.md` 中定义的术语。不要漂移到术语表明确避开的同义词。

如果你需要的概念还不在术语表中，这是一个信号：要么你在发明项目不用的说法（重新考虑），要么存在真实缺口（记下来交给 `/domain-modeling`）。

## 标记 ADR 冲突

如果你的输出与现有 ADR 矛盾，明确指出来，而不是默默覆盖：

> _与 ADR-0007（event-sourced orders）矛盾，但值得重新讨论，因为……_
