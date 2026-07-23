%% 数学软件与实验课程报告
%  基于时间序列与排队论的共享单车需求预测及站点优化分析
%  姓名：________  学号：________
%
%  本脚本完成以下任务：
%    1. 数据加载与预处理
%    2. 需求热力图可视化（按小时×星期）
%    3. ADF平稳性检验与ARIMA(2,1,2)建模预测
%    4. M/M/c排队论仿真与容量灵敏度分析
%    5. 结果汇总与输出
%
%  运行前请确保:
%    - MATLAB Econometrics Toolbox 已安装（用于adftest/arima/autocorr等）
%    - 数据文件 data/hour.csv 存在
%    - 当前工作目录为本脚本所在目录（bike_sharing_analysis/）

clear; clc; close all;
fprintf('============================================\n');
fprintf('   共享单车需求预测及站点优化分析\n');
fprintf('   基于ARIMA时间序列与排队论\n');
fprintf('============================================\n\n');

%% 1. 数据加载与预处理
fprintf('【步骤1】数据加载与预处理...\n\n');

% 定义路径（自动定位到项目根目录）
script_dir = fileparts(mfilename('fullpath'));
DATA_FILE = fullfile(script_dir, '..', '..', 'data', 'hour.csv');
FIG_DIR   = fullfile(script_dir, '..', '..', 'figures');

if ~exist(DATA_FILE, 'file')
    error('数据文件 hour.csv 不存在，请检查路径。');
end
if ~exist(FIG_DIR, 'dir')
    mkdir(FIG_DIR);
end

% 读取CSV数据
opts = detectImportOptions(DATA_FILE);
data = readtable(DATA_FILE, opts);
fprintf('数据加载完成: 共 %d 条记录, %d 个字段\n', height(data), width(data));

% 构建datetime列（dteday + hr）
dteday_str = cellstr(data.dteday);
data.datetime = NaT(height(data), 1);
for i = 1:height(data)
    data.datetime(i) = datetime(dteday_str{i}, 'InputFormat', 'yyyy-MM-dd') + ...
                       hours(data.hr(i));
end
data = sortrows(data, 'datetime');

% 标记高峰时段
peak_type = strings(height(data), 1);
for i = 1:height(data)
    h = data.hr(i);
    if h >= 7 && h <= 9
        peak_type(i) = 'Morning Peak (7-9)';
    elseif h >= 17 && h <= 19
        peak_type(i) = 'Evening Peak (17-19)';
    else
        peak_type(i) = 'Off-Peak';
    end
end
data.peak_type = categorical(peak_type);
fprintf('预处理完成. 数据时间范围: %s ~ %s\n', ...
    datestr(min(data.datetime)), datestr(max(data.datetime)));

%% 2. 需求热力图
fprintf('\n【步骤2】生成需求热力图...\n');

% 按 weekday x hr 聚合平均 cnt
[G, weekdays, hours] = findgroups(data.weekday, data.hr);
avg_cnt = splitapply(@mean, data.cnt, G);

% 构造 7x24 热力图矩阵
heatmap_mat = zeros(7, 24);
for i = 1:length(weekdays)
    wd = weekdays(i) + 1;
    hr = hours(i) + 1;
    heatmap_mat(wd, hr) = avg_cnt(i);
end

% 重排为 Mon-Sun 顺序 (MATLAB weekday: Sun=1,Mon=2,...,Sat=7)
% 目标: Mon(2)->1, Tue(3)->2, Wed(4)->3, Thu(5)->4, Fri(6)->5, Sat(7)->6, Sun(1)->7
reorder = [2, 3, 4, 5, 6, 7, 1];
heatmap_mat = heatmap_mat(reorder, :);
day_labels = {'周一', '周二', '周三', '周四', '周五', '周六', '周日'};

figure('Position', [100, 100, 900, 500]);
h = heatmap(0:23, day_labels, heatmap_mat, ...
    'Colormap', parula, 'ColorbarVisible', 'on');
h.Title = '一周内各小时平均单车租赁量热力图';
h.XLabel = '一天中的时间（小时）';
h.YLabel = '星期';
h.CellLabelFormat = '%.0f';
saveas(gcf, fullfile(FIG_DIR, 'demand_heatmap.png'));
fprintf('  -> figures/demand_heatmap.png\n');

%% 3. ARIMA 时间序列建模
fprintf('\n【步骤3】ARIMA 时间序列建模...\n');

% 取最后14天数据（14*24=336小时）
TS_LEN = 336;
FORECAST_STEPS = 24;

if height(data) >= TS_LEN + FORECAST_STEPS
    ts_all     = data.cnt(end-TS_LEN-FORECAST_STEPS+1:end);
    ts_time    = data.datetime(end-TS_LEN-FORECAST_STEPS+1:end);
else
    ts_all     = data.cnt;
    ts_time    = data.datetime;
end

train_data = ts_all(1:end-FORECAST_STEPS);
train_time = ts_time(1:end-FORECAST_STEPS);
test_data  = ts_all(end-FORECAST_STEPS+1:end);
test_time  = ts_time(end-FORECAST_STEPS+1:end);

fprintf('训练集: %d 条, 测试集: %d 条\n', length(train_data), length(test_data));

% 3a. ADF 平稳性检验
fprintf('\n--- ADF 平稳性检验 ---\n');
[h_adf, p_adf] = myadftest(train_data);
fprintf('原始序列: h=%d (1=平稳), p=%.6f\n', h_adf, p_adf);

diff_train = diff(train_data);
[h_diff, p_diff] = myadftest(diff_train);
fprintf('一阶差分: h=%d (1=平稳), p=%.6f\n', h_diff, p_diff);

% 3b. ACF/PACF 定阶
figure('Position', [100, 100, 1000, 400]);
subplot(1, 2, 1);
myautocorr(diff_train, 40);
title('一阶差分序列的自相关函数');
subplot(1, 2, 2);
myparcorr(diff_train, 40);
title('一阶差分序列的偏自相关函数');
saveas(gcf, fullfile(FIG_DIR, 'acf_pacf.png'));
fprintf('\nACF/PACF图已保存 -> figures/acf_pacf.png\n');

% 3c. 拟合 ARIMA(2,1,2)
fprintf('\n--- 拟合 ARIMA(2,1,2) ---\n');
est_model = myarima(train_data, 2, 1, 2);
fprintf('模型拟合完成.\n');

% 3d. 预测未来24小时
fprintf('\n--- 预测未来24小时 ---\n');
[Y_f, Y_mse] = myforecast(est_model, train_data, FORECAST_STEPS);
forecast_se = sqrt(Y_mse);
ci_upper = Y_f + 1.96 * forecast_se;
ci_lower = Y_f - 1.96 * forecast_se;

% 3e. 评估指标
rmse_val = sqrt(mean((test_data - Y_f).^2));
mae_val  = mean(abs(test_data - Y_f));
mape_val = mean(abs((test_data - Y_f) ./ (test_data + 1))) * 100;
resid = est_model.residuals(max(est_model.p,est_model.q)+1:end);
[aic_val, bic_val] = myaicbic(resid, 5);

fprintf('预测评估:\n');
fprintf('  RMSE = %.2f\n', rmse_val);
fprintf('  MAE  = %.2f\n', mae_val);
fprintf('  MAPE = %.2f%%\n', mape_val);
fprintf('  AIC  = %.2f\n', aic_val);
fprintf('  BIC  = %.2f\n', bic_val);

% 3f. 绘制预测图
figure('Position', [100, 100, 1200, 500]);
% 显示最近72小时训练数据
n_show = min(72, length(train_data));
plot(train_time(end-n_show+1:end), train_data(end-n_show+1:end), ...
    'b-', 'LineWidth', 1.5, 'DisplayName', '训练数据（最近三天）');
hold on;
plot(test_time, test_data, 'g-', 'LineWidth', 2, ...
    'DisplayName', '实际测试数据（24小时）');
plot(test_time, Y_f, 'r-', 'LineWidth', 2, ...
    'DisplayName', 'ARIMA预测');
fill([test_time; flipud(test_time)], [ci_lower; flipud(ci_upper)], ...
    'r', 'FaceAlpha', 0.12, 'EdgeColor', 'none', ...
    'DisplayName', '95% 置信区间');
hold off;
legend('Location', 'best');
title(sprintf('ARIMA(2,1,2)需求预测  均方根误差=%.1f  平均绝对误差=%.1f', ...
    rmse_val, mae_val));
xlabel('日期 / 时间');
ylabel('小时级需求量 (辆)');
grid on;
datetick('x', 'mm/dd HH:MM', 'keeplimits');
saveas(gcf, fullfile(FIG_DIR, 'arima_forecast.png'));
fprintf('预测图已保存 -> figures/arima_forecast.png\n');

%% 4. 排队论仿真
fprintf('\n【步骤4】M/M/c 排队论仿真...\n');

% 参数设定（基于高峰时段数据）
lambda = 40.0;  % 到达率：高峰时段平均40辆车/小时到达
mu     = 1.2;   % 服务率：每个车位平均处理1.2辆车/小时

fprintf('参数: lambda=%.1f 车/小时, mu=%.1f 车/小时/车位\n', lambda, mu);

capacities = 20:5:60;
n_c = length(capacities);

% 预分配结果数组
P0_arr = zeros(n_c, 1);
Lq_arr = zeros(n_c, 1);
Wq_arr = zeros(n_c, 1);
rho_arr = zeros(n_c, 1);

fprintf('\n仿真结果:\n');
fprintf('  %-10s %-12s %-16s %-16s\n', '容量(c)', '利用率(rho)', '队列长度(Lq)', '等待时间(Wq)');
fprintf('  %-10s %-12s %-16s %-16s\n', '------', '----------', '---------------', '---------------');

for i = 1:n_c
    c = capacities(i);
    [P0_arr(i), Lq_arr(i), Wq_arr(i), rho_arr(i)] = mmc_queue(lambda, mu, c);
    fprintf('  %-10d %-10.1f%% %-16.2f %-12.3f hr (%.1f min)\n', ...
        c, rho_arr(i)*100, Lq_arr(i), Wq_arr(i), Wq_arr(i)*60);
end

% 绘制排队论分析图
figure('Position', [100, 100, 900, 500]);

yyaxis left;
plot(capacities, Wq_arr * 60, 'r-o', 'LineWidth', 2, 'MarkerSize', 8);
ylabel('平均等待时间（分钟）', 'Color', 'r');
ax = gca;
ax.YColor = 'r';

yyaxis right;
plot(capacities, rho_arr * 100, 'b-s', 'LineWidth', 2, 'MarkerSize', 8);
ylabel('系统利用率（%）', 'Color', 'b');
ax.YColor = 'b';

xlabel('停车位容量');
title('M/M/c排队论分析：等待时间与利用率随容量变化');
grid on;
legend({'平均等待时间', '系统利用率'}, 'Location', 'best');
saveas(gcf, fullfile(FIG_DIR, 'queue_analysis.png'));
fprintf('\n排队论分析图已保存 -> figures/queue_analysis.png\n');

%% 5. 结果汇总
fprintf('\n============================================\n');
fprintf('                结果汇总\n');
fprintf('============================================\n\n');

fprintf('【ARIMA时间序列模型】\n');
fprintf('  模型: ARIMA(2,1,2)\n');
fprintf('  预测步长: %d 小时\n', FORECAST_STEPS);
fprintf('  RMSE: %.2f\n', rmse_val);
fprintf('  MAE:  %.2f\n', mae_val);
fprintf('  MAPE: %.2f%%\n', mape_val);
fprintf('  AIC:  %.2f\n', aic_val);
fprintf('  BIC:  %.2f\n', bic_val);

fprintf('\n【排队论分析】\n');
fprintf('  到达率 lambda = %.1f 车/小时\n', lambda);
fprintf('  服务率 mu = %.1f 车/小时/车位\n', mu);

% 找出等待时间 < 5 分钟的最小容量
idx_wq5 = find(Wq_arr * 60 < 5, 1, 'first');
min_c = capacities(idx_wq5);
fprintf('  建议最小容量: c >= %d (等待时间 < 5 分钟)\n', min_c);

% 找出利用率在40%-70%的合理容量范围
idx_rho_ok = find(rho_arr > 0.4 & rho_arr < 0.7);
if ~isempty(idx_rho_ok)
    fprintf('  最优容量范围: %d ~ %d (利用率40%%~70%%)\n', ...
        capacities(idx_rho_ok(1)), capacities(idx_rho_ok(end)));
end

fprintf('\n【输出文件】\n');
fprintf('  热力图:           figures/demand_heatmap.png\n');
fprintf('  ACF/PACF图:       figures/acf_pacf.png\n');
fprintf('  ARIMA预测图:      figures/arima_forecast.png\n');
fprintf('  排队论分析图:     figures/queue_analysis.png\n');

fprintf('\n============================================\n');
fprintf('  程序运行完毕\n');
fprintf('============================================\n');
