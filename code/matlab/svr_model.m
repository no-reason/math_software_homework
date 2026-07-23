%% SVR 机器学习对比模型
% 需要 Statistics and Machine Learning Toolbox
% 使用 fitrsvm 函数实现支持向量回归
% 对比 ARIMA 时间序列模型的预测精度

clear; clc;
fprintf('=== SVR 对比模型 ===\n');

% 加载数据（自动定位路径）
script_dir = fileparts(mfilename('fullpath'));
DATA_DIR = fullfile(script_dir, '..', '..', 'data');
FIG_DIR = fullfile(script_dir, '..', '..', 'figures');
data = readtable(fullfile(DATA_DIR, 'hour.csv'));

% 取最后 360 条记录
recent = data(end-359:end, :);

% 构建特征矩阵: 小时、工作日、温度、湿度、风速、季节
features = [recent.hr, recent.workingday, recent.temp, recent.hum, recent.windspeed, recent.season];
y = recent.cnt;

% 训练/测试划分（最后24小时为测试集）
X_train = features(1:end-24, :);
X_test = features(end-23:end, :);
y_train = y(1:end-24);
y_test = y(end-23:end);

% 标准化特征
mu = mean(X_train);
sigma = std(X_train);
Z_train = (X_train - mu) ./ sigma;
Z_test = (X_test - mu) ./ sigma;

% 训练 SVR 模型（RBF核，BoxConstraint=100）
fprintf('训练 SVR 模型...\n');
svr_mdl = fitrsvm(Z_train, y_train, ...
    'KernelFunction', 'rbf', ...
    'BoxConstraint', 100, ...
    'Epsilon', 0.1, ...
    'Standardize', false, ...
    'KernelScale', 'auto');

% 预测
y_pred = predict(svr_mdl, Z_test);

% 评估
rmse_svr = sqrt(mean((y_test - y_pred).^2));
mae_svr = mean(abs(y_test - y_pred));
mape_svr = mean(abs((y_test - y_pred) ./ (y_test + 1))) * 100;
fprintf('SVR 评估结果:\n');
fprintf('  RMSE = %.2f\n', rmse_svr);
fprintf('  MAE  = %.2f\n', mae_svr);
fprintf('  MAPE = %.2f%%\n', mape_svr);

% 绘制对比图


figure('Position', [100, 100, 1000, 450]);
hold on;
plot(1:24, y_test, 'g-', 'LineWidth', 2, 'DisplayName', '实际值');
plot(1:24, y_pred, 'm-', 'LineWidth', 2, 'DisplayName', sprintf('支持向量回归预测（均方根误差=%.1f）', rmse_svr));
hold off;
xlabel('时间（小时）');
ylabel('需求量（辆）');
title('支持向量回归预测结果');
legend('Location', 'best');
grid on;
if ~exist(FIG_DIR, 'dir'), mkdir(FIG_DIR); end
saveas(gcf, fullfile(FIG_DIR, 'svr_comparison.png'));
fprintf('对比图已保存\n');
fprintf('=== SVR 完成 ===\n');
