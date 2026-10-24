function [cos_aoi, elev] = solar_geometry(W, tilt, lat)
% solar_geometry.m
% Angle of incidence on a south-facing plane and solar elevation, from the
% UTC timestamp of each PVGIS row (Duffie & Beckman relations).
%   cos_aoi : cosine of the angle of incidence on the module plane
%   elev    : solar elevation [deg] (cross-check against PVGIS H_sun)
    n  = W.doy_utc;
    B  = (n - 1) * 360/365;
    EoT = 229.2*(0.000075 + 0.001868*cosd(B) - 0.032077*sind(B) ...
                 - 0.014615*cosd(2*B) - 0.04089*sind(2*B));            % [min]
    delta = 23.45 * sind(360*(284 + n)/365);                           % declination [deg]
    t_solar = W.hr_utc + W.lon/15 + EoT/60;                            % apparent solar time [h]
    omega = 15*(t_solar - 12);                                         % hour angle [deg]

    cosZ  = sind(lat).*sind(delta) + cosd(lat).*cosd(delta).*cosd(omega);
    elev  = asind(max(-1, min(1, cosZ)));
    cos_aoi = sind(delta).*sind(lat - tilt) + cosd(delta).*cosd(lat - tilt).*cosd(omega);
end
