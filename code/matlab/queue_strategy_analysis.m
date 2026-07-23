function strategy = queue_strategy_analysis(lambda, mu, fig_dir)
% QUEUE_STRATEGY_ANALYSIS 排队论调度策略情景分析
%   比较三个情景：
%     1. 基准情景：lambda=40, mu=1.2
%     2. 调度分流：到达率降低10%~15%
%     3. 效率改善：服务率提高

    script_dir = fileparts(mfilename('fullpath'));
    results_dir = fullfile(script_dir, '..', '..', 'results');
    if ~exist(results_dir, 'dir'), mkdir(results_dir); end

    scenarios = {
        '基准(lambda=40,mu=1.2)',  40.0,  1.2;
        '调度分流-10%',           36.0,  1.2;
        '调度分流-15%',           34.0,  1.2;
        '效率改善+20%',           40.0,  1.44;
        '效率改善+30%',           40.0,  1.56;
    };
    
    n_scenarios = size(scenarios, 1);
    capacities = 20:5:60;
    
    % 结果表头
    fid = fopen(fullfile(results_dir, 'queue_strategy_comparison.csv'), 'w');
    fprintf(fid, 'scenario,lambda,mu,c_stable_min,c_wq5_min,c_rec,rho_at_rec,Wq_at_rec_min\n');
    
    strategy = struct();
    
    for s = 1:n_scenarios
        name = scenarios{s,1};
        lam = scenarios{s,2};
        mu_val = scenarios{s,3};
        
        c_stable_min = NaN;   % 最小稳定容量
        c_wq5_min = NaN;      % 等待时间<5分钟的最小容量
        c_rec = NaN;          % 推荐容量
        rho_rec = NaN;
        wq_rec = NaN;
        
        for c = capacities
            rho = lam / (c * mu_val);
            if rho >= 1
                continue; % 不稳定
            end
            
            % 计算排队指标
            sum_term = 0;
            for k = 0:(c-1)
                sum_term = sum_term + (c*rho)^k / factorial(k);
            end
            last_term = (c*rho)^c / (factorial(c) * (1 - rho));
            P0 = 1 / (sum_term + last_term);
            Lq = P0 * (c*rho)^c * rho / (factorial(c) * (1-rho)^2);
            Wq_hours = Lq / lam;
            Wq_min = Wq_hours * 60;
            
            % 记录最小稳定容量
            if isnan(c_stable_min)
                c_stable_min = c;
            end
            
            % 等待时间<5分钟的最小容量
            if Wq_min < 5 && isnan(c_wq5_min)
                c_wq5_min = c;
            end
            
            % 推荐容量：稳定(rho<1) + Wq<5min + 60%<=rho<=85% 的最小容量
            if rho < 1 && Wq_min < 5 && rho >= 0.60 && rho <= 0.85
                if isnan(c_rec)
                    c_rec = c;
                    rho_rec = rho;
                    wq_rec = Wq_min;
                end
            end
        end
        
        % 降级：没找到满足利用率范围的最小容量时，取满足Wq<5的最小容量
        if isnan(c_rec) && ~isnan(c_wq5_min)
            c_rec = c_wq5_min;
            rho_rec = lam / (c_rec * mu_val);
            % 重算Wq
            sum_term = 0;
            for k = 0:(c_rec-1)
                sum_term = sum_term + (c_rec*rho_rec)^k / factorial(k);
            end
            last_term = (c_rec*rho_rec)^c_rec / (factorial(c_rec) * (1 - rho_rec));
            P0_rec = 1 / (sum_term + last_term);
            Lq_rec = P0_rec * (c_rec*rho_rec)^c_rec * rho_rec / (factorial(c_rec) * (1-rho_rec)^2);
            wq_rec = Lq_rec / lam * 60;
        end
        
        % 二级降级：只取最小稳定容量
        if isnan(c_rec) && ~isnan(c_stable_min)
            c_rec = c_stable_min;
            rho_rec = lam / (c_rec * mu_val);
            sum_term = 0;
            for k = 0:(c_rec-1)
                sum_term = sum_term + (c_rec*rho_rec)^k / factorial(k);
            end
            last_term = (c_rec*rho_rec)^c_rec / (factorial(c_rec) * (1 - rho_rec));
            P0_rec = 1 / (sum_term + last_term);
            Lq_rec = P0_rec * (c_rec*rho_rec)^c_rec * rho_rec / (factorial(c_rec) * (1-rho_rec)^2);
            wq_rec = Lq_rec / lam * 60;
        end
        
        strategy.(['s' num2str(s)]) = struct(...
            'scenario', name, 'lambda', lam, 'mu', mu_val, ...
            'c_stable_min', c_stable_min, 'c_wq5_min', c_wq5_min, ...
            'c_rec', c_rec, 'rho_rec', rho_rec, 'wq_rec', wq_rec);
        
        fprintf(fid, '%s,%.1f,%.2f,%d,%d,%d,%.4f,%.2f\n', ...
            name, lam, mu_val, c_stable_min, c_wq5_min, c_rec, rho_rec, wq_rec);
    end
    
    fclose(fid);
    fprintf('  -> results/queue_strategy_comparison.csv\n');
    fprintf('  调度策略分析完成\n');
end
