function stats = compute_descriptive_statistics(data)
% COMPUTE_DESCRIPTIVE_STATISTICS 计算所有描述性统计量
%   输出保存到 results/descriptive_statistics.csv
%   results/seasonal_statistics.csv
%   results/period_descriptive_statistics.csv

    script_dir = fileparts(mfilename('fullpath'));
    results_dir = fullfile(script_dir, '..', '..', 'results');
    if ~exist(results_dir, 'dir'), mkdir(results_dir); end

    % 计算时段标记
    n = height(data);
    peak_type = strings(n, 1);
    is_peak = zeros(n, 1);
    for i = 1:n
        h = data.hr(i);
        if h >= 7 && h <= 9
            peak_type(i) = '早高峰(7-9)'; is_peak(i) = 1;
        elseif h >= 17 && h <= 19
            peak_type(i) = '晚高峰(17-19)'; is_peak(i) = 1;
        elseif h >= 0 && h <= 5
            peak_type(i) = '凌晨(0-5)';
        else
            peak_type(i) = '平峰';
        end
    end
    data.peak_type = peak_type;
    
    % 1. 总体描述性统计
    vars = {'cnt','casual','registered','temp','hum','windspeed'};
    fid = fopen(fullfile(results_dir, 'descriptive_statistics.csv'), 'w');
    fprintf(fid, 'variable,mean,std,min,median,max\n');
    stats = struct();
    for i = 1:length(vars)
        v = data.(vars{i});
        if isnumeric(v)
            s = struct('mean', mean(v), 'std', std(v), 'min', min(v), ...
                       'median', median(v), 'max', max(v));
            stats.(vars{i}) = s;
            fprintf(fid, '%s,%.4f,%.4f,%.4f,%.4f,%.4f\n', vars{i}, s.mean, s.std, s.min, s.median, s.max);
        end
    end
    fclose(fid);
    fprintf('  -> results/descriptive_statistics.csv\n');

    % 2. 时段统计
    fid = fopen(fullfile(results_dir, 'period_descriptive_statistics.csv'), 'w');
    fprintf(fid, 'period,day_type,mean,std,min,median,max\n');
    periods = {'早高峰(7-9)','晚高峰(17-19)','平峰','凌晨(0-5)'};
    day_types = [0, 1]; % 0=周末, 1=工作日
    for p = 1:length(periods)
        for d = 1:length(day_types)
            mask = strcmp(data.peak_type, periods{p}) & data.workingday == day_types(d);
            if sum(mask) > 0
                v = data.cnt(mask);
                dt = iff(day_types(d)==1, '工作日', '周末');
                fprintf(fid, '%s,%s,%.1f,%.1f,%.0f,%.0f,%.0f\n', ...
                    periods{p}, dt, mean(v), std(v), min(v), median(v), max(v));
            end
        end
    end
    fclose(fid);
    fprintf('  -> results/period_descriptive_statistics.csv\n');

    % 3. 季节统计
    season_names = {'春','夏','秋','冬'};
    fid = fopen(fullfile(results_dir, 'seasonal_statistics.csv'), 'w');
    fprintf(fid, 'season,mean_casual,mean_registered,mean_cnt\n');
    for s = 1:4
        mask = data.season == s;
        fprintf(fid, '%s,%.1f,%.1f,%.1f\n', season_names{s}, ...
            mean(data.casual(mask)), mean(data.registered(mask)), mean(data.cnt(mask)));
    end
    fclose(fid);
    fprintf('  -> results/seasonal_statistics.csv\n');

    % 4. 年度对比
    for yr_val = [0, 1]
        mask = data.yr == yr_val;
        yr_name = iff(yr_val==0, '2011', '2012');
        stats.(['daily_avg_' yr_name]) = mean(data.cnt(mask));
    end
    
    % 5. 工作日vs周末关键时段均值
    % 早高峰工作日均值
    mask_am_work = strcmp(data.peak_type, '早高峰(7-9)') & data.workingday == 1;
    stats.am_peak_workday = mean(data.cnt(mask_am_work));
    
    % 晚高峰工作日均值
    mask_pm_work = strcmp(data.peak_type, '晚高峰(17-19)') & data.workingday == 1;
    stats.pm_peak_workday = mean(data.cnt(mask_pm_work));
    
    % 周末峰值
    mask_weekend = data.workingday == 0 & data.hr >= 10 & data.hr <= 16;
    stats.weekend_peak = max(splitapply(@mean, data.cnt(mask_weekend), findgroups(data.hr(mask_weekend))));
    
    fprintf('  描述性统计计算完成\n');
end

function s = iff(cond, t, f)
    if cond, s = t; else s = f; end
end
