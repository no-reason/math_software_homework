%% generate_all_figures.m
% 数学软件大作业：生成全部 MATLAB 图表
% 适用版本：MATLAB R2023b+
%
% 生成文件：
%   1. demand_heatmap.png
%   2. time_series.png
%   3. acf_pacf.png
%   4. arima_forecast.png
%   5. queue_analysis.png
%   6. svr_comparison.png
%
% 使用方法：
%   将本文件放在 code/matlab/ 目录下，直接运行：
%       generate_all_figures
%
% 说明：
%   - 前五张图不依赖 Econometrics Toolbox；
%   - 第六张 SVR 图需要 Statistics and Machine Learning Toolbox；
%   - 本脚本内置 ACF、PACF、ARIMA 和 M/M/c 的计算函数，
%     不依赖仓库中的 myautocorr、myparcorr 等函数。

clear;
clc;
close all;

fprintf('============================================\n');
fprintf('       共享单车项目：生成全部论文图表\n');
fprintf('============================================\n\n');

%% 0. 路径、字体和输出设置
script_dir = fileparts(mfilename('fullpath'));
DATA_FILE = fullfile(script_dir, '..', '..', 'data', 'hour.csv');
FIG_DIR   = fullfile(script_dir, '..', '..', 'figures');

if ~exist(DATA_FILE, 'file')
    error(['未找到数据文件：\n%s\n' ...
           '请将本脚本放在项目的 code/matlab/ 目录下。'], DATA_FILE);
end

if ~exist(FIG_DIR, 'dir')
    mkdir(FIG_DIR);
end

% 根据操作系统选择常见中文字体
if ismac
    chinese_font = 'Heiti SC';
elseif ispc
    chinese_font = 'Microsoft YaHei';
else
    chinese_font = 'Noto Sans CJK SC';
end

set(groot, 'DefaultAxesFontName', chinese_font);
set(groot, 'DefaultTextFontName', chinese_font);
set(groot, 'DefaultLegendFontName', chinese_font);
set(groot, 'DefaultAxesFontSize', 11);
set(groot, 'DefaultFigureColor', 'w');

%% 1. 加载并预处理数据
fprintf('【1/7】加载并预处理数据...\n');

opts = detectImportOptions(DATA_FILE);
data = readtable(DATA_FILE, opts);

required_vars = ["dteday", "hr", "weekday", "workingday", ...
                 "temp", "hum", "windspeed", "season", "cnt"];
missing_vars = setdiff(required_vars, string(data.Properties.VariableNames));

if ~isempty(missing_vars)
    error('hour.csv 缺少字段：%s', char(strjoin(missing_vars, ', ')));
end

% 将应为数值的字段统一转换为 double
numeric_vars = ["hr", "weekday", "workingday", ...
                "temp", "hum", "windspeed", "season", "cnt"];

for i = 1:numel(numeric_vars)
    name = char(numeric_vars(i));
    data.(name) = to_numeric_column(data.(name));
end

% 兼容 dteday 被导入为 datetime、string、char 或 cellstr 的情况
if isdatetime(data.dteday)
    base_date = dateshift(data.dteday, 'start', 'day');
else
    base_date = datetime(string(data.dteday), ...
        'InputFormat', 'yyyy-MM-dd');
end

data.datetime = base_date + hours(data.hr);

% 删除无效记录并按时间排序
valid_rows = ~isnat(data.datetime) & ...
             isfinite(data.hr) & ...
             isfinite(data.weekday) & ...
             isfinite(data.cnt);

data = data(valid_rows, :);
data = sortrows(data, 'datetime');

if height(data) < 80
    error('有效数据不足，当前仅有 %d 条记录。', height(data));
end

fprintf('数据加载完成：%d 条有效记录。\n', height(data));
fprintf('时间范围：%s 至 %s。\n\n', ...
    string(min(data.datetime)), string(max(data.datetime)));

%% 2. 需求热力图
fprintf('【2/7】生成需求热力图...\n');

[group_id, weekday_values, hour_values] = ...
    findgroups(data.weekday, data.hr);

average_count = splitapply(@(x) mean(x, 'omitnan'), ...
    data.cnt, group_id);

heatmap_matrix = NaN(7, 24);

for i = 1:numel(weekday_values)
    row_index = weekday_values(i) + 1;
    col_index = hour_values(i) + 1;

    if row_index >= 1 && row_index <= 7 && ...
       col_index >= 1 && col_index <= 24
        heatmap_matrix(row_index, col_index) = average_count(i);
    end
end

% 原数据 weekday：0=周日，1=周一，...，6=周六
% 重排成：周一至周日
weekday_order = [2, 3, 4, 5, 6, 7, 1];
heatmap_matrix = heatmap_matrix(weekday_order, :);

day_labels = {'周一', '周二', '周三', '周四', ...
              '周五', '周六', '周日'};

fig1 = figure('Position', [100, 100, 1000, 540]);
heatmap_chart = heatmap(0:23, day_labels, heatmap_matrix, ...
    'Colormap', parula, ...
    'ColorbarVisible', 'on');

heatmap_chart.Title = '按小时与星期聚合的平均租赁量';
heatmap_chart.XLabel = '小时';
heatmap_chart.YLabel = '星期';
heatmap_chart.CellLabelFormat = '%.0f';
heatmap_chart.FontName = chinese_font;

save_png(fig1, fullfile(FIG_DIR, 'demand_heatmap.png'));
close(fig1);

%% 3. 时间序列总览图
fprintf('【3/7】生成时间序列总览图...\n');

data.date_only = dateshift(data.datetime, 'start', 'day');

[daily_group, daily_dates] = findgroups(data.date_only);
daily_count = splitapply(@(x) sum(x, 'omitnan'), ...
    data.cnt, daily_group);

recent_30_count = min(30 * 24, height(data));
recent_7_count  = min(7 * 24, height(data));

recent_30 = data(end-recent_30_count+1:end, :);
recent_7  = data(end-recent_7_count+1:end, :);

fig2 = figure('Position', [100, 100, 1400, 900]);
layout2 = tiledlayout(fig2, 3, 1, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

ax21 = nexttile(layout2);
plot(ax21, daily_dates, daily_count, ...
    'Color', [0.13, 0.58, 0.95], ...
    'LineWidth', 0.9);
title(ax21, '日总租赁量（完整数据集）', 'FontWeight', 'bold');
ylabel(ax21, '日租赁量');
grid(ax21, 'on');
xlim(ax21, [daily_dates(1), daily_dates(end)]);

ax22 = nexttile(layout2);
plot(ax22, recent_30.datetime, recent_30.cnt, ...
    'Color', [0.30, 0.75, 0.32], ...
    'LineWidth', 0.7);
title(ax22, '小时级租赁量（最近30天）', 'FontWeight', 'bold');
ylabel(ax22, '小时租赁量');
grid(ax22, 'on');
xlim(ax22, [recent_30.datetime(1), recent_30.datetime(end)]);

ax23 = nexttile(layout2);
plot(ax23, recent_7.datetime, recent_7.cnt, ...
    'Color', [0.96, 0.34, 0.13], ...
    'LineWidth', 0.9);
title(ax23, '小时级租赁量（最近7天）', 'FontWeight', 'bold');
ylabel(ax23, '小时租赁量');
xlabel(ax23, '日期时间');
grid(ax23, 'on');
xlim(ax23, [recent_7.datetime(1), recent_7.datetime(end)]);

save_png(fig2, fullfile(FIG_DIR, 'time_series.png'));
close(fig2);

%% 4. ACF / PACF 图
fprintf('【4/7】生成 ACF/PACF 图...\n');

window_length = min(360, height(data));
ts_data = data.cnt(end-window_length+1:end);
ts_time = data.datetime(end-window_length+1:end);

ts_data = ts_data(:);
diff_ts = diff(ts_data);

max_lag = min(40, length(diff_ts) - 2);

[acf_values, acf_lags, confidence_bound] = ...
    calculate_acf(diff_ts, max_lag);

[pacf_values, pacf_lags] = ...
    calculate_pacf(diff_ts, max_lag);

fig3 = figure('Position', [100, 100, 1100, 460]);
layout3 = tiledlayout(fig3, 1, 2, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

ax31 = nexttile(layout3);
stem(ax31, acf_lags, acf_values, ...
    'filled', 'LineWidth', 1.1, 'MarkerSize', 3);
hold(ax31, 'on');
yline(ax31, confidence_bound, '--r', ...
    '95%置信界限', 'LineWidth', 1);
yline(ax31, -confidence_bound, '--r', 'LineWidth', 1);
yline(ax31, 0, '-k', 'LineWidth', 0.8);
hold(ax31, 'off');
title(ax31, '一阶差分序列的自相关函数');
xlabel(ax31, '滞后阶数');
ylabel(ax31, '自相关系数');
xlim(ax31, [0, max_lag]);
ylim(ax31, [-1, 1]);
grid(ax31, 'on');

ax32 = nexttile(layout3);
stem(ax32, pacf_lags, pacf_values, ...
    'filled', 'LineWidth', 1.1, 'MarkerSize', 3);
hold(ax32, 'on');
yline(ax32, confidence_bound, '--r', ...
    '95%置信界限', 'LineWidth', 1);
yline(ax32, -confidence_bound, '--r', 'LineWidth', 1);
yline(ax32, 0, '-k', 'LineWidth', 0.8);
hold(ax32, 'off');
title(ax32, '一阶差分序列的偏自相关函数');
xlabel(ax32, '滞后阶数');
ylabel(ax32, '偏自相关系数');
xlim(ax32, [0, max_lag]);
ylim(ax32, [-1, 1]);
grid(ax32, 'on');

save_png(fig3, fullfile(FIG_DIR, 'acf_pacf.png'));
close(fig3);

%% 5. ARIMA(2,1,2) 预测图
fprintf('【5/7】生成 ARIMA 预测图...\n');

forecast_steps = 24;

if length(ts_data) <= forecast_steps + 20
    error('用于 ARIMA 的时间序列过短。');
end

train_data = ts_data(1:end-forecast_steps);
test_data  = ts_data(end-forecast_steps+1:end);

train_time = ts_time(1:end-forecast_steps);
test_time  = ts_time(end-forecast_steps+1:end);

arima_model = fit_arima_css(train_data, 2, 1, 2);
[forecast_value, forecast_mse] = ...
    forecast_arima(arima_model, train_data, forecast_steps);

forecast_se = sqrt(max(forecast_mse, 0));
ci_lower = max(forecast_value - 1.96 * forecast_se, 0);
ci_upper = forecast_value + 1.96 * forecast_se;

rmse_arima = sqrt(mean((test_data - forecast_value).^2));
mae_arima  = mean(abs(test_data - forecast_value));
mape_arima = mean(abs((test_data - forecast_value) ./ ...
    max(test_data, 1))) * 100;

fig4 = figure('Position', [100, 100, 1250, 540]);
ax4 = axes(fig4);
hold(ax4, 'on');

% 使用日期序号绘制置信带，避免部分 MATLAB 版本中 fill 对 datetime
% 支持不一致的问题。
x_train_all = datenum(train_time);
x_test = datenum(test_time);

h_ci = fill(ax4, ...
    [x_test; flipud(x_test)], ...
    [ci_lower; flipud(ci_upper)], ...
    [1, 0, 0], ...
    'FaceAlpha', 0.12, ...
    'EdgeColor', 'none');

n_show = min(72, length(train_data));

h_train = plot(ax4, ...
    x_train_all(end-n_show+1:end), ...
    train_data(end-n_show+1:end), ...
    'b-', 'LineWidth', 1.5);

h_actual = plot(ax4, ...
    x_test, test_data, ...
    'g-', 'LineWidth', 2);

h_forecast = plot(ax4, ...
    x_test, forecast_value, ...
    'r-', 'LineWidth', 2);

hold(ax4, 'off');

legend(ax4, ...
    [h_train, h_actual, h_forecast, h_ci], ...
    {'训练数据（最近三天）', ...
     '实际测试数据（24小时）', ...
     'ARIMA预测', ...
     '95%置信区间'}, ...
    'Location', 'best');

xlabel(ax4, '日期时间');
ylabel(ax4, '小时需求量（辆）');
title(ax4, sprintf(['ARIMA(2,1,2)需求预测  ' ...
    'RMSE=%.1f  MAE=%.1f  MAPE=%.1f%%'], ...
    rmse_arima, mae_arima, mape_arima));

grid(ax4, 'on');
datetick(ax4, 'x', 'mm/dd HH:MM', 'keeplimits');

save_png(fig4, fullfile(FIG_DIR, 'arima_forecast.png'));
close(fig4);

fprintf('ARIMA评估：RMSE=%.2f，MAE=%.2f，MAPE=%.2f%%。\n', ...
    rmse_arima, mae_arima, mape_arima);

%% 6. M/M/c 排队论分析图
fprintf('【6/7】生成排队论分析图...\n');

lambda = 40.0;
mu = 1.2;
capacities = (20:5:60)';

n_capacity = numel(capacities);
waiting_minutes = NaN(n_capacity, 1);
utilization_percent = NaN(n_capacity, 1);
queue_length = NaN(n_capacity, 1);

for i = 1:n_capacity
    c = capacities(i);

    [~, queue_length(i), waiting_hours, rho] = ...
        mmc_queue_stable(lambda, mu, c);

    waiting_minutes(i) = waiting_hours * 60;
    utilization_percent(i) = rho * 100;
end

fig5 = figure('Position', [100, 100, 1000, 540]);
ax5 = axes(fig5);

yyaxis(ax5, 'left');
h_wait = plot(ax5, capacities, waiting_minutes, ...
    'r-o', 'LineWidth', 2, 'MarkerSize', 7, ...
    'MarkerFaceColor', 'r');
ylabel(ax5, '平均等待时间（分钟）');
ax5.YColor = [0.85, 0.10, 0.10];

yyaxis(ax5, 'right');
h_rho = plot(ax5, capacities, utilization_percent, ...
    'b-s', 'LineWidth', 2, 'MarkerSize', 7, ...
    'MarkerFaceColor', 'b');
ylabel(ax5, '系统利用率（%）');
ax5.YColor = [0.10, 0.25, 0.85];

xlabel(ax5, '停车位容量');
title(ax5, 'M/M/c排队论分析：不同容量下的等待时间与利用率');
grid(ax5, 'on');
legend(ax5, [h_wait, h_rho], ...
    {'平均等待时间', '系统利用率'}, ...
    'Location', 'best');

save_png(fig5, fullfile(FIG_DIR, 'queue_analysis.png'));
close(fig5);

%% 7. SVR 对比预测图
fprintf('【7/7】生成 SVR 对比图...\n');

if exist('fitrsvm', 'file') ~= 2
    warning(['未检测到 fitrsvm。前五张图已正常生成，但 SVR 图被跳过。\n' ...
             '请安装 Statistics and Machine Learning Toolbox 后重新运行。']);
else
    svr_window = min(360, height(data));
    recent_data = data(end-svr_window+1:end, :);

    features = [recent_data.hr, ...
                recent_data.workingday, ...
                recent_data.temp, ...
                recent_data.hum, ...
                recent_data.windspeed, ...
                recent_data.season];

    response = recent_data.cnt;

    X_train = features(1:end-forecast_steps, :);
    X_test  = features(end-forecast_steps+1:end, :);
    y_train = response(1:end-forecast_steps);
    y_test  = response(end-forecast_steps+1:end);

    feature_mean = mean(X_train, 1);
    feature_std  = std(X_train, 0, 1);
    feature_std(feature_std == 0 | ~isfinite(feature_std)) = 1;

    Z_train = (X_train - feature_mean) ./ feature_std;
    Z_test  = (X_test - feature_mean) ./ feature_std;

    svr_model = fitrsvm(Z_train, y_train, ...
        'KernelFunction', 'rbf', ...
        'BoxConstraint', 100, ...
        'Epsilon', 0.1, ...
        'Standardize', false, ...
        'KernelScale', 'auto');

    svr_prediction = predict(svr_model, Z_test);
    svr_prediction = max(svr_prediction, 0);

    rmse_svr = sqrt(mean((y_test - svr_prediction).^2));
    mae_svr  = mean(abs(y_test - svr_prediction));
    mape_svr = mean(abs((y_test - svr_prediction) ./ ...
        max(y_test, 1))) * 100;

    fig6 = figure('Position', [100, 100, 1050, 480]);
    ax6 = axes(fig6);

    hold(ax6, 'on');
    plot(ax6, 1:forecast_steps, y_test, ...
        'g-o', 'LineWidth', 2, ...
        'MarkerSize', 4, ...
        'DisplayName', '实际值');

    plot(ax6, 1:forecast_steps, svr_prediction, ...
        'm-s', 'LineWidth', 2, ...
        'MarkerSize', 4, ...
        'DisplayName', sprintf('SVR预测（RMSE=%.1f）', rmse_svr));
    hold(ax6, 'off');

    xlabel(ax6, '预测时刻（小时）');
    ylabel(ax6, '需求量（辆）');
    title(ax6, sprintf(['支持向量回归预测结果  ' ...
        'RMSE=%.1f  MAE=%.1f  MAPE=%.1f%%'], ...
        rmse_svr, mae_svr, mape_svr));

    legend(ax6, 'Location', 'best');
    grid(ax6, 'on');
    xlim(ax6, [1, forecast_steps]);
    xticks(ax6, 1:2:forecast_steps);

    save_png(fig6, fullfile(FIG_DIR, 'svr_comparison.png'));
    close(fig6);

    fprintf('SVR评估：RMSE=%.2f，MAE=%.2f，MAPE=%.2f%%。\n', ...
        rmse_svr, mae_svr, mape_svr);
end

fprintf('\n============================================\n');
fprintf('全部可生成图表已输出到：\n%s\n', FIG_DIR);
fprintf('============================================\n');

%% ======================== 局部函数 ========================

function numeric_data = to_numeric_column(column_data)
% 将 table 中的数值、逻辑、分类、字符串或元胞列转换为 double。

    if isnumeric(column_data) || islogical(column_data)
        numeric_data = double(column_data);
    else
        numeric_data = str2double(string(column_data));
    end

    numeric_data = numeric_data(:);
end

function save_png(fig_handle, output_file)
% 刷新图形并以 300 dpi 输出 PNG。

    drawnow;
    exportgraphics(fig_handle, output_file, ...
        'Resolution', 300, ...
        'BackgroundColor', 'white');

    fprintf('  已保存：%s\n', output_file);
end

function [acf_values, lags, bound] = calculate_acf(series, max_lag)
% 计算含 0 阶滞后的样本自相关函数。

    series = series(:);
    series = series(isfinite(series));
    centered = series - mean(series);

    denominator = sum(centered .^ 2);

    if denominator <= eps
        error('差分序列为常数，无法计算 ACF。');
    end

    acf_values = zeros(max_lag + 1, 1);
    lags = (0:max_lag)';

    for k = 0:max_lag
        acf_values(k + 1) = ...
            sum(centered(1:end-k) .* centered(1+k:end)) / ...
            denominator;
    end

    bound = 1.96 / sqrt(length(series));
end

function [pacf_values, lags] = calculate_pacf(series, max_lag)
% 通过逐阶 AR 回归计算偏自相关函数。

    series = series(:);
    series = series(isfinite(series));
    centered = series - mean(series);

    pacf_values = zeros(max_lag + 1, 1);
    pacf_values(1) = 1;
    lags = (0:max_lag)';

    for k = 1:max_lag
        target = centered(k+1:end);
        X = zeros(length(target), k);

        for j = 1:k
            X(:, j) = centered(k-j+1:end-j);
        end

        coefficients = X \ target;
        pacf_values(k + 1) = coefficients(end);
    end
end

function model = fit_arima_css(y_train, p, d, q)
% 使用条件最小二乘法拟合简化 ARIMA(p,d,q) 模型。

    y_train = y_train(:);
    differenced = y_train;

    for i = 1:d
        differenced = diff(differenced);
    end

    n = length(differenced);
    max_lag = max(p, q);

    if n <= max_lag + 2
        error('ARIMA(%d,%d,%d) 的训练样本不足。', p, d, q);
    end

    observation_count = n - max_lag;
    target = differenced(max_lag+1:end);

    % 先拟合 AR(p)，获得 MA 项的初始残差
    X_ar = ones(observation_count, 1 + p);

    for t = 1:observation_count
        index = max_lag + t;

        for j = 1:p
            X_ar(t, 1+j) = differenced(index-j);
        end
    end

    beta_ar = X_ar \ target;

    residuals = zeros(n, 1);
    residuals(max_lag+1:end) = target - X_ar * beta_ar;

    beta_old = [];
    beta = zeros(1 + p + q, 1);

    for iteration = 1:100
        X = ones(observation_count, 1 + p + q);

        for t = 1:observation_count
            index = max_lag + t;

            for j = 1:p
                X(t, 1+j) = differenced(index-j);
            end

            for j = 1:q
                X(t, 1+p+j) = residuals(index-j);
            end
        end

        beta = X \ target;

        new_residuals = zeros(n, 1);
        new_residuals(max_lag+1:end) = target - X * beta;

        if ~isempty(beta_old) && norm(beta - beta_old) < 1e-6
            residuals = new_residuals;
            break;
        end

        beta_old = beta;
        residuals = new_residuals;
    end

    effective_residuals = residuals(max_lag+1:end);
    parameter_count = 1 + p + q;
    denominator = max(length(effective_residuals) - parameter_count, 1);

    model.c = beta(1);
    model.phi = beta(2:1+p);
    model.theta = beta(2+p:1+p+q);
    model.sigma2 = sum(effective_residuals .^ 2) / denominator;
    model.p = p;
    model.d = d;
    model.q = q;
    model.residuals = residuals;
end

function [forecast_value, forecast_mse] = ...
    forecast_arima(model, original_series, forecast_steps)
% 对简化 ARIMA 模型进行多步递推预测。

    original_series = original_series(:);
    differenced = original_series;

    for i = 1:model.d
        differenced = diff(differenced);
    end

    n = length(differenced);

    extended_series = [differenced; zeros(forecast_steps, 1)];
    extended_error = [model.residuals; zeros(forecast_steps, 1)];

    for h = 1:forecast_steps
        index = n + h;
        next_value = model.c;

        for j = 1:model.p
            next_value = next_value + ...
                model.phi(j) * extended_series(index-j);
        end

        for j = 1:model.q
            next_value = next_value + ...
                model.theta(j) * extended_error(index-j);
        end

        extended_series(index) = next_value;
    end

    differenced_forecast = extended_series(n+1:end);
    forecast_value = zeros(forecast_steps, 1);

    if model.d == 0
        forecast_value = differenced_forecast;
    elseif model.d == 1
        forecast_value(1) = original_series(end) + ...
            differenced_forecast(1);

        for h = 2:forecast_steps
            forecast_value(h) = forecast_value(h-1) + ...
                differenced_forecast(h);
        end
    else
        error('当前预测函数仅支持 d=0 或 d=1。');
    end

    % 简化的多步预测误差方差近似
    forecast_mse = (1:forecast_steps)' * model.sigma2;
end

function [P0, Lq, Wq, rho] = mmc_queue_stable(lambda, mu, c)
% 数值稳定地计算 M/M/c 排队模型。
% Wq 单位为小时。

    rho = lambda / (c * mu);

    if rho >= 1
        P0 = NaN;
        Lq = NaN;
        Wq = NaN;
        return;
    end

    offered_load = lambda / mu;

    k = (0:c-1)';
    log_terms = k .* log(offered_load) - gammaln(k + 1);
    sum_term = sum(exp(log_terms));

    log_c_term = c * log(offered_load) - gammaln(c + 1);
    c_term = exp(log_c_term);

    last_term = c_term / (1 - rho);
    P0 = 1 / (sum_term + last_term);

    Lq = P0 * c_term * rho / (1 - rho)^2;
    Wq = Lq / lambda;
end
