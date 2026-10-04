本项目文件夹是边缘检测模块第二版
本项目文件夹包含edge_detection_basic和testbench.其中前者为边缘检测模块代码，后者为仿真测试代码。
本项目运行条件：下载了Efinity,icarus verilog（用于仿真）,gtkwave(用于读取仿真结果)；并将其bin文件夹添加为系统环境变量
本项目仿真运行方法：在readme所属文件夹中打开cmd,运行efx_run.bat edge_detection_basic.xml --flow rtlsim
本项目重要文件：
    edge_detection_basic.v：边缘检测模块代码
    testbench.v:仿真测试代码
    sim.vcd:仿真结果，使用gtkwave查看。为了上传删除了，运行之后就会出来
    edge_result.pgm:仿真结果显示图片
    其他文件不要动。

说明：
此版本添加了中值去噪程序。by GPT
在overflow文件夹中可以获取log