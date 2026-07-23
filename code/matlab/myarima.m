function model = myarima(y_train, p, d, q)
    % Step 1: Difference
    w = y_train;
    for i = 1:d
        w = diff(w);
    end
    n = length(w);
    maxlag = max(p, q);
    if n <= maxlag + 2
        error('Too few observations for ARIMA(%d,%d,%d)', p, d, q);
    end
    T = n - maxlag;
    y_vec = w(maxlag+1:end);

    % Step 2: Fit AR(p) to get initial residuals for MA terms
    X_ar = ones(T, 1 + p);
    for t = 1:T
        idx = maxlag + t;
        for j = 1:p
            X_ar(t, 1+j) = w(idx - j);
        end
    end
    beta_ar = (X_ar'*X_ar)\(X_ar'*y_vec);
    e = zeros(n, 1);
    e(maxlag+1:end) = y_vec - X_ar * beta_ar;

    % Step 3: Iterative CSS for ARMA(p,q)
    for iter = 1:100
        X = ones(T, 1 + p + q);
        for t = 1:T
            idx = maxlag + t;
            for j = 1:p
                X(t, 1+j) = w(idx - j);
            end
            for j = 1:q
                X(t, 1+p+j) = e(idx - j);
            end
        end
        beta = (X'*X)\(X'*y_vec);
        e_new = zeros(n, 1);
        e_new(maxlag+1:end) = y_vec - X * beta;
        if iter > 1 && norm(beta - beta_old) < 1e-6
            break;
        end
        beta_old = beta;
        e = e_new;
    end
    model.c = beta(1);
    model.phi = beta(2:1+p);
    model.theta = beta(2+p:1+p+q);
    model.sigma2 = (e'*e) / (n - maxlag);
    model.p = p; model.d = d; model.q = q;
    model.residuals = e;
end
