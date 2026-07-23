function [yf, ymse] = myforecast(model, y, num_steps)
    w = y;
    for i = 1:model.d
        w = diff(w);
    end
    n_w = length(w);
    maxlag = max(model.p, model.q);
    w_ext = [w; zeros(num_steps, 1)];
    e_ext = [model.residuals; zeros(num_steps, 1)];
    for h = 1:num_steps
        idx = n_w + h;
        w_ext(idx) = model.c;
        for j = 1:model.p
            w_ext(idx) = w_ext(idx) + model.phi(j) * w_ext(idx - j);
        end
        for j = 1:model.q
            w_ext(idx) = w_ext(idx) + model.theta(j) * e_ext(idx - j);
        end
    end
    wf = w_ext(n_w+1:end);
    yf = zeros(num_steps, 1);
    for h = 1:num_steps
        if model.d == 1
            if h == 1
                yf(h) = y(end) + wf(h);
            else
                yf(h) = yf(h-1) + wf(h);
            end
        else
            yf(h) = wf(h);
        end
    end
    ymse = (1:num_steps)' * model.sigma2;
end
