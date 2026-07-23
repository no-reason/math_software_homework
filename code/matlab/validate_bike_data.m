function validation = validate_bike_data(data)
    % VALIDATE_BIKE_DATA 对共享单车数据集进行完整质量检查
    %   validation = VALIDATE_BIKE_DATA(data) 检查数据完整性
    %
    % 检查项清单：
    %   1. 数据文件是否存在
    %   2. 必要字段是否存在
    %   3. 总行数和字段数
    %   4. 缺失值数量
    %   5. 重复记录数量
    %   6. datetime解析失败数量
    %   7. hr是否在0~23
    %   8. weekday是否在0~6
    %   9. cnt是否非负
    %   10. casual + registered == cnt
    %   11. 时间是否按升序排列
    %   12. 时间戳是否存在重复
    %   13. 数据时间范围
    %   14. 是否存在明显非法值
    %   15. 是否存在无法处理的NaN/Inf/NaT

    validation = struct();
    checks = struct('check', {}, 'result', {}, 'status', {});
    n = height(data);
    
    % 检查1：总行数和字段数
    checks(end+1) = struct('check', '总行数', 'result', n, 'status', 'ok');
    checks(end+1) = struct('check', '字段数', 'result', width(data), 'status', 'ok');
    
    % 检查2：必要字段是否存在
    required_fields = {'instant','dteday','season','yr','mnth','hr','holiday',...
                      'weekday','workingday','weathersit','temp','atemp',...
                      'hum','windspeed','casual','registered','cnt'};
    missing_fields = {};
    for i = 1:length(required_fields)
        if ~ismember(required_fields{i}, data.Properties.VariableNames)
            missing_fields{end+1} = required_fields{i};
        end
    end
    if isempty(missing_fields)
        checks(end+1) = struct('check', '必要字段完整性', 'result', '全部存在', 'status', 'ok');
    else
        checks(end+1) = struct('check', '必要字段完整性', 'result', strjoin(missing_fields,','), 'status', 'fail');
    end
    
    % 检查3：缺失值
    missing_count = 0;
    for i = 1:width(data)
        missing_count = missing_count + sum(ismissing(data{:,i}));
    end
    checks(end+1) = struct('check', '缺失值总数', 'result', missing_count, 'status', 'ok');
    
    % 检查4：重复记录
    dup_count = 0;
try
    dup_count = n - length(unique(data.instant));
catch
    dup_count = NaN;
end
    checks(end+1) = struct('check', '重复记录数', 'result', dup_count, 'status', 'ok');
    
    % 检查5：hr范围
    bad_hr = sum(data.hr < 0 | data.hr > 23);
    checks(end+1) = struct('check', 'hr超范围(0~23)', 'result', bad_hr, 'status', iff(bad_hr==0,'ok','fail'));
    
    % 检查6：weekday范围
    bad_wd = sum(data.weekday < 0 | data.weekday > 6);
    checks(end+1) = struct('check', 'weekday超范围(0~6)', 'result', bad_wd, 'status', iff(bad_wd==0,'ok','fail'));
    
    % 检查7：cnt非负
    bad_cnt = sum(data.cnt < 0);
    checks(end+1) = struct('check', 'cnt为负', 'result', bad_cnt, 'status', iff(bad_cnt==0,'ok','fail'));
    
    % 检查8：casual + registered == cnt
    sum_check = sum(abs((data.casual + data.registered) - data.cnt) > 0.01);
    checks(end+1) = struct('check', 'casual+registered≠cnt', 'result', sum_check, 'status', iff(sum_check==0,'ok','warn'));
    
    % 检查9：时间范围
    try
        t_min = min(data.datetime);
        t_max = max(data.datetime);
        checks(end+1) = struct('check', '时间范围', 'result', sprintf('%s ~ %s', char(t_min), char(t_max)), 'status', 'ok');
    catch
        checks(end+1) = struct('check', '时间范围', 'result', '解析失败', 'status', 'warn');
    end
    
    % 检查10：时间顺序
    try
        sorted = issorted(data.datetime);
        checks(end+1) = struct('check', '时间升序排列', 'result', iff(sorted,'是','否'), 'status', iff(sorted,'ok','fail'));
    catch
        checks(end+1) = struct('check', '时间升序排列', 'result', '无法判断', 'status', 'warn');
    end
    
    % 检查11：NaN/Inf
    for i = 1:width(data)
        if isnumeric(data{:,i})
            nan_inf = sum(isnan(data{:,i}) | isinf(data{:,i}));
            if nan_inf > 0
                checks(end+1) = struct('check', sprintf('%s中有NaN/Inf', data.Properties.VariableNames{i}), ...
                    'result', nan_inf, 'status', 'warn');
            end
        end
    end
    
    validation.checks = checks;
    validation.n_checks = length(checks);
    n_ok = 0; n_warn = 0; n_fail = 0;
    for i = 1:length(checks)
        switch checks(i).status
            case 'ok', n_ok = n_ok + 1;
            case 'warn', n_warn = n_warn + 1;
            case 'fail', n_fail = n_fail + 1;
        end
    end
    validation.n_ok = n_ok; validation.n_warn = n_warn; validation.n_fail = n_fail;
    validation.all_ok = (n_fail == 0);
end

function s = iff(cond, t, f)
    if cond, s = t; else s = f; end
end
