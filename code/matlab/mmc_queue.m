function [P0, Lq, Wq, rho] = mmc_queue(lambda, mu, c)
% MMC_QUEUE M/M/c 排队论模型核心计算
%   [P0, Lq, Wq, rho] = MMC_QUEUE(lambda, mu, c) 计算 M/M/c 排队系统的
%   稳态概率 P0、平均队列长度 Lq、平均等待时间 Wq（小时）和系统利用率 rho。
%
%   输入:
%       lambda - 平均到达率（顾客/小时）
%       mu     - 每个服务台的平均服务率（顾客/小时/台）
%       c      - 并行服务台数量
%
%   输出:
%       P0 - 系统空闲概率
%       Lq - 平均队列长度
%       Wq - 平均等待时间（小时）
%       rho - 系统利用率

    rho = lambda / (c * mu);
    
    % 检查系统稳定性
    if rho >= 1
        % 对于不稳定系统，不抛出异常，而是返回 NaN/Inf 以便外层循环继续
        P0 = NaN;
        Lq = NaN;
        Wq = NaN;
        return;
    end
    
    % 计算 P0 (系统空闲概率)
    sum_term = 0;
    for k = 0:(c-1)
        sum_term = sum_term + (c*rho)^k / factorial(k);
    end
    last_term = (c*rho)^c / (factorial(c) * (1 - rho));
    P0 = 1 / (sum_term + last_term);
    
    % 计算 Lq (平均队列长度)
    Lq = P0 * (c*rho)^c * rho / (factorial(c) * (1-rho)^2);
    
    % 计算 Wq (平均等待时间，小时)
    Wq = Lq / lambda;
end
