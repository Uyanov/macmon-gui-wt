# 07: 暂停时 resize 及时重绘（#3）

**What to build:** 暂停中改变窗口尺寸不再等 15 秒墙钟兜底：立即按新尺寸重绘。

**Blocked by:** 06

**Status:** ready-for-agent

- [ ] 暂停 + 窗口 100x30→60x20 后 1 秒内按新尺寸正确渲染
- [ ] 未暂停路径无回归
