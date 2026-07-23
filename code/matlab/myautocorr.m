function [acf, lags, bounds] = myautocorr(y, nlags)
    n = length(y);
    y_m = y - mean(y);
    c0 = y_m' * y_m / n;
    acf = zeros(nlags, 1);
    for k = 1:nlags
        ck = y_m(1:end-k)' * y_m(k+1:end) / n;
        acf(k) = ck / c0;
    end
    lags = (1:nlags)';
    bounds = 1.96 / sqrt(n) * ones(nlags, 1);
end
