function [h, pValue, stat, cValue, method] = myadftest(y, model_type, lags)
% MYADFTEST ADF单位根检验（自动检测工具箱）
%   优先使用 Econometrics Toolbox 的官方 adftest
%   不可用时使用 OLS 手动实现
%
%   输出：
%     h       - 检验结果（0=不能拒绝单位根，1=拒绝单位根）
%     pValue  - p值（手动实现时为空[]）
%     stat    - ADF统计量
%     cValue  - 临界值 [1%, 5%, 10%]
%     method  - 使用的方法 ('econometrics_toolbox' 或 'manual_ols')

    if nargin < 2, model_type = 'AR'; end
    if nargin < 3, lags = []; end
    
    % 检查 Econometrics Toolbox
    if license('test', 'econometrics_toolbox') && exist('adftest', 'file') == 2
        % 使用官方 adftest
        if isempty(lags)
            [h, pValue, stat, cValue] = adftest(y, 'model', model_type);
        else
            [h, pValue, stat, cValue] = adftest(y, 'model', model_type, 'lags', lags);
        end
        method = 'econometrics_toolbox';
        return;
    end
    
    % 手动 OLS 实现（仅报告统计量和临界值，不计算p值）
    fprintf('  [INFO] Econometrics Toolbox 不可用，使用手动 ADF 实现\n');
    fprintf('  [WARN] 手动 ADF 仅报告统计量和临界值，不计算精确 p 值\n');
    
    dy = diff(y);
    n = length(dy);
    y_lag = y(1:end-1);
    
    if isempty(lags)
        lags = max(1, round((n-1)^(1/3)));
    end
    lags = min(lags, n - 3);
    
    % 构建回归矩阵
    X = [];
    switch model_type
        case 'AR'
            X = y_lag(:);
        case 'ARD'
            X = [ones(n,1), y_lag(:)];
        case 'TS'
            X = [ones(n,1), (1:n)', y_lag(:)];
    end
    
    % 添加差分滞后项
    for i = 1:lags
        dY_lag_i = [zeros(i,1); dy(1:end-i)];
        X = [X, dY_lag_i];
    end
    
    % 去除前 lags 个观测
    valid = lags+1:n;
    X = X(valid, :);
    dy_v = dy(valid);
    
    % OLS
    beta = (X'*X)\(X'*dy_v);
    resid = dy_v - X*beta;
    mse = (resid'*resid) / (length(dy_v) - size(X,2));
    se = sqrt(mse * diag(inv(X'*X)));
    
    % ADF统计量 = gamma的t统计量（y_lag的系数）
    if strcmp(model_type, 'AR')
        gamma_idx = 1;
    elseif strcmp(model_type, 'ARD')
        gamma_idx = 2;
    else
        gamma_idx = 3;
    end
    stat = beta(gamma_idx) / se(gamma_idx);
    
    % MacKinnon 临界值（近似）
    % 样本量 n=500 时的临界值（MacKinnon 1996, Table 1）
    switch model_type
        case 'AR'
            cValue = [-2.58, -1.95, -1.62];  % 无常数无趋势
        case 'ARD'
            cValue = [-3.43, -2.86, -2.57];  % 有常数无趋势
        case 'TS'
            cValue = [-3.96, -3.41, -3.12];  % 有常数有趋势
        otherwise
            cValue = [-3.43, -2.86, -2.57];
    end
    
    h = stat < cValue(2);  % 5%水平
    pValue = [];  % 手动实现不计算精确p值
    method = 'manual_ols';
end
