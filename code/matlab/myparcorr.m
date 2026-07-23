function [pacf, lags, bounds] = myparcorr(y, nlags)
    n = length(y);
    y_m = y - mean(y);
    pacf = zeros(nlags, 1);
    for k = 1:nlags
        X = zeros(n-k, k);
        for j = 1:k
            X(:, j) = y_m(k-j+1:end-j);
        end
        y_vec = y_m(k+1:end);
        phi = (X'*X)\(X'*y_vec);
        pacf(k) = phi(end);
    end
    lags = (1:nlags)';
    bounds = 1.96 / sqrt(n) * ones(nlags, 1);
end
