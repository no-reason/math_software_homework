function [aic_val, bic_val] = myaicbic(residuals, numParams)
    n = length(residuals);
    logL = -n/2 * (log(2*pi) + log(residuals'*residuals/n) + 1);
    aic_val = -2*logL + 2*numParams;
    bic_val = -2*logL + numParams*log(n);
end
