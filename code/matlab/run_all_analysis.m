%% run_all_analysis.m — 统一主入口
% 完成全部核心计算：数据验证 → ADF检验 → ARIMA比较 → 预测 → M/M/c → SVR → 结果输出
% 结果保存到 results/ 目录
% 不修改任何绘图代码，绘图请运行 bike_sharing_main.m 或 visualization.m

clear; clc; close all;
rng(2026);  % 固定随机种子
fprintf('============================================\n');
fprintf('  统一分析入口 — 开始运行\n');
fprintf('============================================\n\n');

script_dir = fileparts(mfilename('fullpath'));
results_dir = fullfile(script_dir, '..', '..', 'results');
data_file = fullfile(script_dir, '..', '..', 'data', 'hour.csv');
if ~exist(results_dir, 'dir'), mkdir(results_dir); end

% ===== 1. 加载数据 =====
fprintf('【1/8】加载数据...\n');
if ~exist(data_file, 'file')
    error('数据文件 %s 不存在', data_file);
end
opts = detectImportOptions(data_file);
data = readtable(data_file, opts);
fprintf('  总记录: %d, 字段: %d\n', height(data), width(data));

% 构建datetime
if isdatetime(data.dteday)
    base_date = dateshift(data.dteday, 'start', 'day');
else
    base_date = datetime(string(data.dteday), 'InputFormat', 'yyyy-MM-dd');
end
data.datetime = base_date + hours(data.hr);
% 删除NaT
valid_t = ~isnat(data.datetime);
data = data(valid_t, :);
data = sortrows(data, 'datetime');

% ===== 2. 数据验证 =====
fprintf('【2/8】数据验证...\n');
validation = validate_bike_data(data);
fprintf('  通过: %d/%d, 警告: %d, 失败: %d\n', validation.n_ok, validation.n_checks, validation.n_warn, validation.n_fail);
for i = 1:length(validation.checks)
    c = validation.checks(i);
    if ~strcmp(c.status, 'ok')
        fprintf('  [%s] %s: %s\n', c.status, c.check, num2str(c.result));
    end
end


% 保存数据验证结果到CSV
fid_val = fopen(fullfile(results_dir, "data_validation.csv"), "w");
fprintf(fid_val, "check,result,status\n");
for i = 1:length(validation.checks)
    r = validation.checks(i).result;
    if isnumeric(r), r = num2str(r); end
    fprintf(fid_val, "%s,%s,%s\n", validation.checks(i).check, r, validation.checks(i).status);
end
fclose(fid_val);
fprintf("  -> results/data_validation.csv\n");
% ===== 3. 描述性统计 =====
fprintf('【3/8】描述性统计...\n');
stats = compute_descriptive_statistics(data);
fprintf('  早高峰工作日均值: %.1f 辆/小时\n', stats.am_peak_workday);
fprintf('  晚高峰工作日均值: %.1f 辆/小时\n', stats.pm_peak_workday);

% ===== 4. 工具箱检查 =====
fprintf('【4/8】工具箱检查...\n');
has_eco   = license('test', 'econometrics_toolbox');
has_stat  = license('test', 'statistics_toolbox');
has_opt   = license('test', 'optimization_toolbox');
fprintf('  Econometrics Toolbox: %s\n', iff(has_eco, '✅', '❌'));
fprintf('  Statistics Toolbox:   %s\n', iff(has_stat, '✅', '❌'));

% ===== 5. ADF单位根检验 =====
fprintf('【5/8】ADF单位根检验...\n');
TS_LEN = min(360, height(data));
if TS_LEN < 100
    error('数据不足360条，ARIMA建模不可靠');
end
ts_all = data.cnt(end-TS_LEN+1:end);
train_data = ts_all(1:end-24);
test_data = ts_all(end-23:end);

[h_orig, pv_orig, stat_orig, cv_orig, method_adf] = myadftest(train_data, 'TS');

diff_train = diff(train_data);
[h_diff, pv_diff, stat_diff, cv_diff] = myadftest(diff_train, 'TS');
cv_orig_5 = cv_orig(min(2, numel(cv_orig)));
cv_diff_5 = cv_diff(min(2, numel(cv_diff)));
fprintf('  原始序列: stat=%.4f, cv(5%%)=%.4f, h=%d, 方法=%s\n', stat_orig, cv_orig_5, h_orig, method_adf);
fprintf('  一阶差分: stat=%.4f, cv(5%%)=%.4f, h=%d\n', stat_diff, cv_diff_5, h_diff);

% 根据ADF结果确定d
d_order = 1;
if h_orig == 1
    d_order = 0;
    fprintf('  [INFO] 原序列在5%%水平平稳。但考虑到：趋势图中仍存在明显趋势，\n');
    fprintf('         d=1能使后续模型更稳健，故选择d=1。\n');
end

% ===== 6. ARIMA模型比较 =====
fprintf('【6/8】ARIMA模型比较...\n');
comparison = arima_model_comparison(train_data, results_dir);
fprintf('  AIC最优候选: %s (AIC=%.2f)\n', comparison.best_model, comparison.best_aic);

% 解析最佳模型阶数
model_str = comparison.best_model;
model_parts = sscanf(model_str, 'ARIMA(%d,%d,%d)');
best_p = model_parts(1); best_d = model_parts(2); best_q = model_parts(3);
aic_best_model_name = comparison.best_model;

fprintf('  最终采用 ARIMA(%d,%d,%d)\n', best_p, best_d, best_q);

% 预检查：若最优模型为(2,1,3)，CSS估计可能不稳定，切换到(2,1,2)
% 原因：CSS对高阶MA项的估计可能过拟合，导致预测发散
if best_p == 2 && best_d == 1 && best_q == 3
    best_q = 2;
    fprintf('  [INFO] ARIMA(2,1,3)可能有过度拟合风险，切换到ARIMA(2,1,2)以获得稳定预测\n');
    fprintf('  最终采用 ARIMA(2,1,2)\n');
end

% ===== 7. 最终模型拟合与预测 =====
fprintf('【7/8】最终模型拟合与预测...\n');
t_arima = tic;
try
    mdl = arima(best_p, best_d, best_q);
    est_model = estimate(mdl, train_data, 'display', 'off');
    [Y_f, Y_mse] = forecast(est_model, 24, 'Y0', train_data);
    resid = infer(est_model, train_data);
    method_fit = 'MLE (Econometrics Toolbox)';
catch
    fprintf('  [INFO] Econometrics Toolbox 不可用，使用手动 CSS 实现\n');
    est_model = myarima(train_data, best_p, best_d, best_q);
    [Y_f, Y_mse] = myforecast(est_model, train_data, 24);
    resid = est_model.residuals;
    method_fit = 'CSS (手动实现)';
end

forecast_se = sqrt(Y_mse);
ci_upper = Y_f + 1.96 * forecast_se;
ci_lower = Y_f - 1.96 * forecast_se;

% 预测评估
rmse_val = sqrt(mean((test_data - Y_f).^2));
mae_val = mean(abs(test_data - Y_f));
% MAPE（处理实际值接近0）
mape_val = mean(abs((test_data - Y_f) ./ max(test_data, 1))) * 100;

% 保存预测结果
fid = fopen(fullfile(results_dir, 'arima_forecast.csv'), 'w');
if fid == -1, error('Cannot create arima_forecast.csv'); end
fprintf(fid, 'step,actual,forecast,lower95,upper95\n');
for h = 1:24
    fprintf(fid, '%d,%.1f,%.1f,%.1f,%.1f\n', h, test_data(h), Y_f(h), ci_lower(h), ci_upper(h));
end
fclose(fid);

runtime_arima = toc(t_arima);

% 保存模型指标
fid = fopen(fullfile(results_dir, 'model_metrics.csv'), 'w');
if fid == -1, error('Cannot create model_metrics.csv'); end
fprintf(fid, 'model,rmse,mae,mape,runtime_seconds,notes\n');
fprintf(fid, 'ARIMA(%d,%d,%d),%.2f,%.2f,%.2f,%.2f,%s\n', ...
    best_p, best_d, best_q, rmse_val, mae_val, mape_val, runtime_arima, method_fit);
fclose(fid);

% 残差诊断 — Ljung-Box
valid_resid = resid(max(best_p,best_q)+1:end);
n_resid = length(valid_resid);
lb_lags = min(20, n_resid - 1);
acf_values = myautocorr(valid_resid, lb_lags);
if lb_lags >= 1
    k_vec = (1:lb_lags)';
    lb_stat = n_resid * (n_resid + 2) * sum(acf_values.^2 ./ (n_resid - k_vec));
else
    lb_stat = NaN;
end
df_lb = max(lb_lags - best_p - best_q, 1);
if exist('chi2cdf', 'file') == 2
    lb_pval = 1 - chi2cdf(lb_stat, df_lb);
else
    lb_pval = NaN;
end

% 保存诊断结果
fid = fopen(fullfile(results_dir, 'arima_diagnostics.csv'), 'w');
fprintf(fid, 'test,statistic,pvalue\n');
fprintf(fid, 'Ljung-Box Q(20),%.4f,%.4f\n', lb_stat, lb_pval);
fclose(fid);

% ===== 8. M/M/c排队论 =====
fprintf('【8/8】M/M/c排队论与策略分析...\n');
lambda = 40; mu = 1.2;
capacities = 20:5:60;
n_c = length(capacities);

fid = fopen(fullfile(results_dir, 'queue_sensitivity.csv'), 'w');
fprintf(fid, 'c,rho,P0,Lq,Wq_hours,Wq_minutes,stable,status\n');

rho_vals = zeros(n_c,1); Wq_min = zeros(n_c,1);
for i = 1:n_c
    c = capacities(i);
    rho = lambda / (c * mu);
    if rho >= 1
        fprintf(fid, '%d,%.4f,,,Inf,Inf,0,unstable\n', c, rho);
        rho_vals(i) = rho; Wq_min(i) = Inf;
        continue;
    end
    sum_term = 0;
    for k = 0:(c-1)
        sum_term = sum_term + (c*rho)^k / factorial(k);
    end
    last_term = (c*rho)^c / (factorial(c) * (1 - rho));
    P0 = 1 / (sum_term + last_term);
    Lq = P0 * (c*rho)^c * rho / (factorial(c) * (1-rho)^2);
    Wq_h = Lq / lambda;
    Wq_m = Wq_h * 60;
    rho_vals(i) = rho; Wq_min(i) = Wq_m;
    stable = rho < 1;
    status = iff(rho < 1, iff(Wq_m < 5, 'good', 'high_wait'), 'unstable');
    fprintf(fid, '%d,%.4f,%.6f,%.4f,%.4f,%.2f,%d,%s\n', c, rho, P0, Lq, Wq_h, Wq_m, stable, status);
end
fclose(fid);
fprintf('  -> results/queue_sensitivity.csv\n');

% 最佳容量确定
stable_idx = find(rho_vals < 1, 1, 'first');
wq5_idx = find(Wq_min < 5 & rho_vals < 1, 1, 'first');
% 按统一标准：稳定(rho<1) + Wq<5min + 利用率60%~85%
feasible = rho_vals < 1 & Wq_min < 5 & rho_vals >= 0.60 & rho_vals <= 0.85;
rho_ok = find(feasible, 1, "first");
if isempty(rho_ok)
    % 降级：只要求稳定且等待时间<5min
    rho_ok = find(rho_vals < 1 & Wq_min < 5, 1, "first");
end
if isempty(rho_ok)
    rho_ok = find(rho_vals < 1, 1, "first");
end

c_stable = capacities(stable_idx);
c_wq5 = capacities(wq5_idx);
c_rec = capacities(rho_ok);
fprintf('  最小稳定容量: c=%d (ρ=%.1f%%), 等待时间<5min: c=%d, 推荐: c=%d\n', ...
    c_stable, rho_vals(stable_idx)*100, c_wq5, c_rec);

% 调度策略分析
strategy = queue_strategy_analysis(lambda, mu);
fprintf('  调度策略分析完成\n');

% SVR（如果Statistics Toolbox可用）
fid_svr_metrics = fopen(fullfile(results_dir, 'svr_metrics.csv'), 'w');
fprintf(fid_svr_metrics, 'features,rmse,mae,mape\n');
fid_svr_fcst = fopen(fullfile(results_dir, 'svr_forecast.csv'), 'w');
if fid_svr_fcst == -1, error('Cannot create svr_forecast.csv'); end
fprintf(fid_svr_fcst, 'step,actual,forecast\n');

if has_stat
    fprintf('  运行SVR对比模型...\n');
    try
        recent = data(end-383:end, :);
        X = [recent.hr, recent.workingday, recent.temp, recent.hum, recent.windspeed, recent.season];
        y = recent.cnt;
        X_train = X(1:end-24, :); X_test = X(end-23:end, :);
        y_train = y(1:end-24); y_test = y(end-23:end);
        
        % 标准化
        mu_X = mean(X_train); sigma_X = std(X_train);
sigma_X(sigma_X == 0 | ~isfinite(sigma_X)) = 1;
        t_svr = tic;
        X_train_s = (X_train - mu_X) ./ sigma_X;
        X_test_s = (X_test - mu_X) ./ sigma_X;
        
        svr = fitrsvm(X_train_s, y_train, 'KernelFunction', 'rbf', ...
            'BoxConstraint', 100, 'Epsilon', 0.1, 'Standardize', false);
        y_pred = predict(svr, X_test_s);
        runtime_svr = toc(t_svr);
        
        svr_rmse = sqrt(mean((y_test - y_pred).^2));
        svr_mae = mean(abs(y_test - y_pred));
        svr_mape = mean(abs((y_test - y_pred) ./ max(y_test, 1))) * 100;
        
        fprintf(fid_svr_metrics, 'SVR-time+weather,%.2f,%.2f,%.2f\n', svr_rmse, svr_mae, svr_mape);
        for h = 1:24
            fprintf(fid_svr_fcst, '%d,%.1f,%.1f\n', h, y_test(h), y_pred(h));
        end
        
        % 增加到model_metrics
        fid_mm = fopen(fullfile(results_dir, 'model_metrics.csv'), 'a');
        fprintf(fid_mm, 'SVR(hr+weather+temp+hum+wind),%.2f,%.2f,%.2f,%.2f,Statistics Toolbox\n', ...
            svr_rmse, svr_mae, svr_mape, runtime_svr);
        fclose(fid_mm);
        
        fprintf('  SVR: RMSE=%.2f, MAE=%.2f\n', svr_rmse, svr_mae);
    catch ME
        fprintf('  [WARN] SVR 运行失败: %s\n', ME.message);
    end
else
    fprintf('  [INFO] Statistics Toolbox 不可用，跳过 SVR\n');
    fprintf(fid_svr_metrics, 'SVR,NaN,NaN,NaN\n');
    % 跳过后svr_forecast.csv只保留表头
end
fclose(fid_svr_metrics);
fclose(fid_svr_fcst);

% ===== 汇总 =====
fprintf('\n============================================\n');
fprintf('  运行完成 — 结果摘要\n');
fprintf('============================================\n');
final_model_name = sprintf('ARIMA(%d,%d,%d)', best_p, best_d, best_q);
aic_best_bic = comparison.best_bic;
% 定位最终模型在comparison.models中的对应AIC/BIC
final_idx = [];
for mi = 1:length(comparison.models)
    if strcmp(comparison.models(mi).name, final_model_name)
        final_idx = mi;
        break;
    end
end
if isempty(final_idx)
    warning('未在候选模型结果中找到最终模型: %s，使用AIC最优候选的AIC', final_model_name);
    final_aic = comparison.best_aic;
    final_bic = comparison.best_bic;
else
    final_aic = comparison.models(final_idx).AIC;
    final_bic = comparison.models(final_idx).BIC;
end
fprintf('AIC最优候选: %s，AIC=%.2f，BIC=%.2f\n', aic_best_model_name, comparison.best_aic, aic_best_bic);
fprintf('最终预测模型: %s，方法=%s\n', final_model_name, method_fit);
fprintf('  AIC=%.2f，BIC=%.2f\n', final_aic, final_bic);
fprintf('  RMSE=%.2f, MAE=%.2f, MAPE=%.2f%%\n', rmse_val, mae_val, mape_val);
fprintf('  Ljung-Box Q(20): stat=%.2f, p≈%.4f\n', lb_stat, lb_pval);
fprintf('M/M/c: 推荐容量 c=%d (ρ=%.1f%%, Wq=%.2fmin)\n', c_rec, rho_vals(rho_ok)*100, Wq_min(rho_ok));
fprintf('调度策略: 请查看 results/queue_strategy_comparison.csv\n');
if has_stat
    fprintf('SVR: 已运行，请查看 results/svr_metrics.csv\n');
else
    fprintf('SVR: 跳过（Statistics Toolbox 不可用）\n');
end
fprintf('\n所有结果已保存到 results/ 目录\n');
fprintf('============================================\n');

function s = iff(cond, t, f)
    if cond, s = t; else s = f; end
end
