function comparison = arima_model_comparison(train_data, results_dir)
% ARIMA_MODEL_COMPARISON 候选ARIMA模型比较
%   比较多个(p,d,q)组合的AIC/BIC
%   保存到 results/arima_model_comparison.csv
    
    if nargin < 2
        script_dir = fileparts(mfilename('fullpath'));
        results_dir = fullfile(script_dir, '..', '..', 'results');
    end
    
    % 候选模型列表
    candidates = [
        0, 1, 1;  1, 1, 0;  1, 1, 1;
        2, 1, 0;  0, 1, 2;  2, 1, 1;
        1, 1, 2;  2, 1, 2;  3, 1, 1;
        1, 1, 3;  3, 1, 2;  2, 1, 3
    ];
    
    % 检查 Econometrics Toolbox
    has_toolbox = license('test', 'econometrics_toolbox') && exist('arima', 'file') == 2;
    
    n_models = size(candidates, 1);
    
    % 初始化返回结构
    comparison = struct();
    comparison.has_toolbox = has_toolbox;
    comparison.method = iff(has_toolbox, 'MLE (Econometrics Toolbox)', 'CSS (手动实现)');
    
    % 准备模型列表数组
    model_names = cell(n_models, 1);
    aic_vals = NaN(n_models, 1);
    bic_vals = NaN(n_models, 1);
    logL_vals = NaN(n_models, 1);
    methods = cell(n_models, 1);
    statuses = cell(n_models, 1);
    
    % CSV结果
    csv_rows = cell(n_models + 1, 8);
    csv_rows(1,:) = {'model','p','d','q','logL','AIC','BIC','method'};
    
    for m = 1:n_models
        p = candidates(m, 1);
        d = candidates(m, 2);
        q = candidates(m, 3);
        model_name = sprintf('ARIMA(%d,%d,%d)', p, d, q);
        model_names{m} = model_name;
        
        try
            if has_toolbox
                % 使用官方工具箱
                mdl = arima(p, d, q);
                [est, ~, logL] = estimate(mdl, train_data, 'display', 'off');
                resid = infer(est, train_data);
                k = p + q + 1;
                n = length(train_data);
                aic = -2*logL + 2*k;
                bic = -2*logL + k*log(n);
                method_used = 'toolbox';
                csv_rows(m+1,:) = {model_name, p, d, q, logL, aic, bic, method_used};
            else
                % 使用手动 CSS 实现
                model_m = myarima(train_data, p, d, q);
                resid = model_m.residuals;
                n = length(resid);
                valid_resid = resid(max(p,q)+1:end);
                n_valid = length(valid_resid);
                k = p + q + 1;
                ssr = valid_resid' * valid_resid;
                logL = -n_valid/2 * (log(2*pi) + log(ssr/n_valid) + 1);
                aic = -2*logL + 2*k;
                bic = -2*logL + k*log(n_valid);
                method_used = 'css';
                csv_rows(m+1,:) = {model_name, p, d, q, logL, aic, bic, method_used};
            end
            aic_vals(m) = aic;
            bic_vals(m) = bic;
            logL_vals(m) = logL;
            methods{m} = method_used;
            statuses{m} = 'success';
        catch ME
            csv_rows(m+1,:) = {model_name, p, d, q, NaN, NaN, NaN, 'failed'};
            methods{m} = 'failed';
            statuses{m} = 'failed';
            fprintf('  [WARN] %s 估计失败: %s\n', model_name, ME.message);
        end
    end
    
    % 构建 comparison.models 结构数组
    comp_models = struct('name', cell(n_models,1), 'p', cell(n_models,1), ...
        'd', cell(n_models,1), 'q', cell(n_models,1), ...
        'logL', cell(n_models,1), 'AIC', cell(n_models,1), ...
        'BIC', cell(n_models,1), 'method', cell(n_models,1), ...
        'status', cell(n_models,1));
    for m = 1:n_models
        comp_models(m).name = model_names{m};
        comp_models(m).p = candidates(m, 1);
        comp_models(m).d = candidates(m, 2);
        comp_models(m).q = candidates(m, 3);
        comp_models(m).logL = logL_vals(m);
        comp_models(m).AIC = aic_vals(m);
        comp_models(m).BIC = bic_vals(m);
        comp_models(m).method = iff(isempty(methods{m}), 'failed', methods{m});
        comp_models(m).status = statuses{m};
    end
    comparison.models = comp_models;
    
    % 找出AIC最小的模型
    [min_aic, best_idx] = min(aic_vals, [], 'omitnan');
    if all(isnan(aic_vals))
        error('所有候选ARIMA模型均估计失败，无法选择最终模型。');
    end
    comparison.best_model = model_names{best_idx};
    comparison.best_aic = min_aic;
    comparison.best_bic = bic_vals(best_idx);
    comparison.best_logL = logL_vals(best_idx);
    
    % 保存CSV
    fid = fopen(fullfile(results_dir, 'arima_model_comparison.csv'), 'w');
    fprintf(fid, '%s,%s,%s,%s,%s,%s,%s,%s\n', csv_rows{1,:});
    for m = 1:n_models
        fprintf(fid, '%s,%d,%d,%d,%.4f,%.4f,%.4f,%s\n', csv_rows{m+1,:});
    end
    fclose(fid);
    fprintf('  -> results/arima_model_comparison.csv\n');
    fprintf('  最佳模型: %s (AIC=%.2f)\n', comparison.best_model, min_aic);
end

function s = iff(cond, t, f)
    if cond, s = t; else s = f; end
end
