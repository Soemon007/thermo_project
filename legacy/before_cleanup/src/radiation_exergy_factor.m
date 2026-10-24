function psi = radiation_exergy_factor(eps_dil, T0, Ts)
% radiation_exergy_factor.m
% Exergy-to-energy ratio of DILUTED blackbody radiation (Petela; Landsberg & Tonge 1979).
%
% Radiation with spectral radiance eps*B(T_sun) (a "grey-diluted" blackbody):
%   energy flux   E = eps * sigma * Ts^4
%   entropy flux  S = (4/3) * eps * sigma * Ts^3 * X(eps)
%   X(eps) = 45/(4 pi^4 eps) * Int_0^inf x^2 [ (1+n) ln(1+n) - n ln n ] dx,  n = eps/(e^x - 1)
% X(1) = 1 (undiluted sunlight); X grows as the light is spread out, i.e. diffuse sky
% light carries more entropy per joule and less exergy.
%
%   psi = 1 - T0*S/E = 1 - (4/3) (T0/Ts) X(eps)
% (the Petela environment term (1/3)(T0/Ts)^4 is < 1e-5 for direct sunlight and is not
%  defined for strongly diluted radiation, so it is left out here; pv_model keeps the
%  full Petela factor for the direct beam.)
%
% eps_dil, T0 : arrays of the same size (T0 in K); Ts scalar [K].
% X is tabulated once (persistent) on a log grid of eps and interpolated.

    persistent logE Xtab
    if isempty(Xtab)
        logE = linspace(-10, 0, 201);
        x = logspace(-6, log10(80), 6000);
        Xtab = zeros(size(logE));
        for k = 1:numel(logE)
            e = 10^logE(k);
            n = e ./ expm1(x);
            g = x.^2 .* ((1 + n).*log1p(n) - n.*log(max(n, realmin)));
            Xtab(k) = 45/(4*pi^4*e) * trapz(x, g);
        end
        Xtab = Xtab / Xtab(end);      % exact normalisation X(1) = 1 (removes quadrature bias)
    end
    le  = log10(min(max(eps_dil, 1e-10), 1));
    X   = interp1(logE, Xtab, le, 'linear');
    psi = 1 - (4/3) * (T0 / Ts) .* X;
end
