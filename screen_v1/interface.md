# display_top 模块接口说明文档
## 模块概述
模块：`display_top`
功能：接收上游边缘检测模块输出的像素数据，通过异步FIFO跨时钟域，产生640*480@60Hz LCD时序信号，输出并行RGB与同步信号给到LVDS IP。
依赖RTL文件：`display_top.v`、`vga_640_480_timing.v`
依赖IP：`fifo_async_8bit_2048`（Efinity异步FIFO，由顶层工程创建）

---

## 端口列表
| 端口名 | 方向 | 位宽 | 时钟域 | 说明 |
| ---- | ---- | ---- | ---- | ---- |
| sys_clk_100m | input | 1bit | 100MHz | 系统时钟，上游像素写入时钟域 |
| pix_clk_25m | input | 1bit | 25MHz | LCD像素时钟，屏幕读出时序时钟域 |
| rst_n | input | 1bit | 全局 | 低电平全局复位，同时复位FIFO与时序模块 |
| din | input | [7:0] | sys_clk_100m | 上游输入灰度像素数据 |
| wen | input | 1bit | sys_clk_100m | FIFO写使能，高电平有效，写入din |
| fifo_full | output | 1bit | sys_clk_100m | FIFO满标志。1=FIFO已满，上游必须停止写 |
| fifo_empty | output | 1bit | pix_clk_25m | FIFO空标志。1=FIFO无数据，屏幕无像素输出 |
| pix_clk | output | 1bit | pix_clk_25m | 输出到LVDS IP的像素时钟 |
| hs | output | 1bit | pix_clk_25m | LCD行同步信号 |
| vs | output | 1bit | pix_clk_25m | LCD场同步信号 |
| de | output | 1bit | pix_clk_25m | 数据有效信号，高电平RGB数据有效 |
| rgb_out | output reg | [23:0] | pix_clk_25m | 24bit RGB并行像素输出，R[23:16],G[15:8],B[7:0] |

---

## 时钟域约定
1. **写侧（上游 → display_top）**：所有 `din, wen, fifo_full` 同步于 `sys_clk_100m`
2. **读侧（display_top → LVDS）**：所有 `pix_clk, hs, vs, de, rgb_out, fifo_empty` 同步于 `pix_clk_25m`
3. 跨时钟域处理：模块内部使用异步FIFO完成100M→25M跨时钟域隔离

---

## 握手时序约定（上游边缘检测模块）
1. 当 `fifo_full == 1`，上游**立即拉低wen，停止发送像素din**，否则FIFO溢出，图像错乱。
2. 当 `fifo_full == 0`，上游可以持续拉高wen，每个100M时钟送入一组din像素。
3. 帧无强制握手信号，依靠FIFO缓存；上游持续送像素，模块自动读出并刷新屏幕。

> 注意：上游送图速率不能长期高于LCD显示速率，否则FIFO持续变满触发流量控制。

---

## 输出侧（display_top → LVDS IP）
1. 时序标准：640×480@60Hz，像素时钟25MHz
2. `de=1` 区间为屏幕有效像素区域，此时rgb_out有效；de=0时RGB数据无效，可忽略。
3. `hs` 行同步、`vs` 场同步为标准VGA时序，直接送入LVDS TX IP。

---

## IP依赖说明
IP名称：`fifo_async_8bit_2048`
- 类型：异步FIFO
- 写位宽：8bit，读位宽：8bit
- 深度：2048
- 写时钟：sys_clk_100m，读时钟：pix_clk_25m
- 复位：低有效复位 wr_rst_n / rd_rst_n
> 顶层工程需要在Efinity IP Manager新建该IP，参数严格保持一致。

---

## 集成注意事项
1. 顶层工程负责生成两路时钟 `sys_clk_100m`、`pix_clk_25m`（由PLL IP产生），本模块不包含PLL。
2. LVDS TX IP由顶层工程例化，接收本模块输出的pix_clk/hs/vs/de/rgb_out。
3. 复位信号 `rst_n` 上电保持低电平一段时间，之后释放为高。
4. 综合工具：Efinity 2025.1，器件：Ti60F225。
