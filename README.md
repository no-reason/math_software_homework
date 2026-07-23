# 数学软件与实验课程大作业

## 基于时间序列与排队论的共享单车需求预测及站点优化分析

本项目是《数学软件与实验》课程大作业，**完全使用 MATLAB** 对共享单车系统进行需求预测和站点容量优化分析。

## 项目结构

```
├── code/matlab/                 # MATLAB 源代码（全部代码）
│   ├── run_all_analysis.m       # ★ 统一主入口（运行全部核心分析）
│   ├── bike_sharing_main.m      # 主程序（完整工作流+绘图）
│   ├── visualization.m          # 可视化脚本（已手动修复中文标签）
│   ├── svr_model.m              # SVR 对比模型
│   ├── mmc_queue.m              # M/M/c 排队论函数
│   ├── validate_bike_data.m     # 数据质量验证（15项检查）
│   ├── compute_descriptive_statistics.m  # 描述性统计量计算
│   ├── arima_model_comparison.m # 候选ARIMA模型自动比较
│   ├── queue_strategy_analysis.m # 调度策略情景分析
│   ├── myadftest.m              # ADF 单位根检验（支持工具箱/手动）
│   ├── myautocorr.m             # 自相关函数（手动实现）
│   ├── myparcorr.m              # 偏自相关函数（手动实现）
│   ├── myarima.m                # ARIMA 条件最小二乘估计（手动实现）
│   ├── myforecast.m             # ARIMA 递推预测（手动实现）
│   └── myaicbic.m               # AIC/BIC 计算（手动实现）
├── data/                        # 数据集（UCI Bike Sharing）
│   └── hour.csv
├── figures/                     # 全部可视化图表（中文标签）
│   ├── demand_heatmap.png       # 图1：需求热力图
│   ├── time_series.png          # 图2：时间序列总览
│   ├── acf_pacf.png             # 图3：ACF/PACF
│   ├── arima_forecast.png       # 图4：ARIMA预测
│   ├── queue_analysis.png       # 图5：排队论分析
│   └── svr_comparison.png       # 图6：SVR对比
├── results/                     # 代码运行输出CSV
│   ├── data_validation.csv
│   ├── descriptive_statistics.csv
│   ├── period_descriptive_statistics.csv
│   ├── seasonal_statistics.csv
│   ├── arima_model_comparison.csv
│   ├── model_metrics.csv
│   ├── arima_forecast.csv
│   ├── arima_diagnostics.csv
│   ├── queue_sensitivity.csv
│   ├── queue_strategy_comparison.csv
│   ├── svr_metrics.csv
│   └── svr_forecast.csv
├── paper/
│   ├── main.tex                 # LaTeX 论文源码
│   └── main.pdf                 # 最终 PDF 报告
├── reports/                     # 分析建模报告
└── README.md                    # 本文件
```

## 论文概述

中文，LaTeX 排版（xelatex），STSongti SC 字体。

### 章节结构

| 章节 | 内容 |
|------|------|
| 引言 | 共享单车行业背景、潮汐效应、技术路线图 |
| 文献综述 | 需求预测研究现状、排队论应用、本文定位 |
| 数据来源与探索性分析 | UCI数据集、描述性统计、热力图、时序图 |
| ARIMA时间序列模型 | ADF检验、候选模型比较、AIC/BIC定阶、预测 |
| M/M/c排队论模型 | Erlang C公式、容量灵敏度分析、调度策略情景 |
| 结果分析与讨论 | 时段误差分解、模型对比、局限性 |
| 结论与展望 | 主要发现、未来研究方向 |

### 关键结果

| 模型 | RMSE | MAE | AIC | BIC |
|------|------|-----|-----|-----|
| ARIMA(2,1,2) | 95.21 | 76.16 | 3764.75 | 3783.79 |
| SVR（RBF核，hr+天气+温度+湿度+风速） | 50.82 | 43.08 | — | — |

> 注：AIC最优候选模型为ARIMA(2,1,3)，但在手动CSS实现下该模型多步预测稳定性较差，综合模型复杂度与预测稳定性后最终采用ARIMA(2,1,2)。

- **推荐站点容量**：c=40（ρ=83.3%，Wq=1.43min），推荐弹性区间 40~45
- **潮汐效应**：工作日早高峰时段均值约336辆/小时、晚高峰约455辆/小时
- **排队论**：c=35 时等待 20.9min，c=40 时降至 1.43min，c=45 时仅 0.16min

### 可视化图表

所有图表均为 MATLAB 生成：
- 需求热力图（按小时×星期聚合）
- ACF/PACF 自相关/偏自相关图
- ARIMA(2,1,2) 24小时预测 + 95% 置信带
- M/M/c 容量-等待时间-利用率分析图
- SVR 支持向量回归预测对比

## 模型与方法

1. **ARIMA(2,1,2) 时间序列模型** — 条件平方和（CSS）估计，AIC最优候选为ARIMA(2,1,3)，但综合预测稳定性后最终采用ARIMA(2,1,2)
2. **M/M/c 排队论模型** — Erlang C 公式，容量灵敏度分析与调度策略情景模拟
3. **SVR 支持向量回归** — MATLAB fitrsvm函数（RBF核），融合小时、工作日、季节、温度、湿度、风速等特征（注：使用测试期天气数据作为理想化天气预报代理）

## 运行方法

### 环境要求
- MATLAB R2023b+
  - Statistics and Machine Learning Toolbox（SVR需要，无此工具箱时自动跳过）
  - Econometrics Toolbox（可选，无此工具箱时使用手动实现代码）
- LaTeX 发行版（xelatex，用于编译论文）

### MATLAB 代码
```bash
cd code/matlab
# ★ 唯一核心入口：运行全部核心计算与结果输出
/Applications/MATLAB_R2026a.app/bin/matlab -batch "run_all_analysis"
# 绘图脚本（单独运行，生成figures/中的图表）
/Applications/MATLAB_R2026a.app/bin/matlab -batch "visualization"
```

### 编译论文
```bash
cd paper
xelatex main.tex
xelatex main.tex    # 第二遍解决交叉引用
```

## 最终数值说明

所有论文中的定量结果均由 `code/matlab/run_all_analysis.m` 实际计算后输出到 `results/` 目录。最终数值以本地运行生成的 CSV 文件为准。

## 数据来源

UCI Machine Learning Repository - Bike Sharing Dataset（Fanaee-T & Gama, 2014）

https://archive.ics.uci.edu/ml/datasets/Bike+Sharing+Dataset

## GitHub

https://github.com/no-reason/math_software_homework
