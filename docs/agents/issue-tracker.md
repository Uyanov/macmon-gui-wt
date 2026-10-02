# Issue 跟踪：本地 Markdown

本仓库的 issue 和 spec 以 Markdown 文件形式存放在 `.scratch/` 下。

## 约定

- 一个功能一个目录：`.scratch/<feature-slug>/`
- spec 是 `.scratch/<feature-slug>/spec.md`
- 实现 issue 一个 ticket 一个文件：`.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号，禁止把所有 tickets 合并成一个文件
- triage 状态记录为每个 issue 文件顶部的 `Status:` 行（角色字符串见 `triage-labels.md`）
- 评论与讨论历史追加到文件底部 `## Comments` 标题下

## 当技能说 "publish to the issue tracker"

在 `.scratch/<feature-slug>/` 下新建文件（需要时创建目录）。

## 当技能说 "fetch the relevant ticket"

读取对应路径的文件。用户通常会直接给出路径或 issue 编号。

## Wayfinding 操作

供 `/wayfinder` 使用。**map** 是一个文件，**child** 是它的子文件。

- **Map**：`.scratch/<effort>/map.md`（承载 Notes / Decisions-so-far / Fog 正文）。
- **Child ticket**：`.scratch/<effort>/issues/NN-<slug>.md`，从 `01` 编号，正文放问题。`Type:` 行记录 ticket 类型（`research`/`prototype`/`grilling`/`task`）；`Status:` 行记录 `claimed`/`resolved`。
- **阻塞**：顶部附近 `Blocked by: NN, NN` 行。所列为空的 ticket 即解除阻塞。
- **Frontier**：扫描 `.scratch/<effort>/issues/`，找未关闭、无阻塞、未被认领的文件；编号最小者优先。
- **认领**：开工前先写 `Status: claimed` 并保存。
- **解决**：在 `## Answer` 标题下追加答案，置 `Status: resolved`，然后把上下文指针（要点 + 链接）追加到 `map.md` 的 Decisions-so-far。
