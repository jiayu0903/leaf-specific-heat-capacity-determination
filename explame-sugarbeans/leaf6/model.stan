functions {
  int setSpline(real x, real xmax, array[] real values);
  real getSVal(int idx, real x);
  
  real lcheck(real t, array[] real tON, array[] real dt, array[] real Qabs, int N) {
    for (i in 1:N) {
      if (t > tON[i] && t < (tON[i] + dt[i]))
        return Qabs[i];
    }  
    return 0.;
  }
  
  real SatVap(real Tc) {
    return(613.65 * exp(17.502 * Tc / (240.97 + Tc))); // Pa
  }
  
  real LatentHeat(real Tk) {
    return(1.91846E6 * pow(Tk / (Tk - 33.91), 2)); // J Kg-1
  }
  
  vector derivs(real t, vector y,
                real gbl, real gsw, real k, array[] real Qabs,
                array[] real tON, array[] real dt, int N) {
    
    real Tair = getSVal(0, t);
    real RH = getSVal(1, t);
    real Treflect = getSVal(2, t);
    real Pa = 101300.;
    
    real rho = Pa / (287.058 * (Tair + 273.));
    real ea = SatVap(Tair) * RH;
    real SH = 0.622 * ea / (Pa - ea);
    real Cs = 1005. + 1820. * SH;
    
    real SW = lcheck(t, tON, dt, Qabs, N);
    real LW = 2. * 0.9846 * 5.6703E-8 * (pow(Treflect + 273., 4) - pow(y[1] + 273., 4));
    real R = SW + LW;
    
    real C = 2. * rho * Cs * gbl * (y[1] - Tair);
    
    real lambda = LatentHeat(y[1] + 273.);
    real vpd = SatVap(y[1]) - ea;
    real gtw_leaf = 1. / (1. / gsw + 0.92 / gbl);
    real lE = lambda * 0.622 * rho / Pa * gtw_leaf * vpd;
    
    vector[1] dydt;
    dydt[1] = (R - C - lE) / k;
    return dydt;
  }
}

data {
  int N1;
  int N2;
  int N3;
  int N4;
  array[N2] real tON;
  array[N3] real ts;
  array[N4] real dt;
  array[N1] real Tair;
  array[N1] real RH;
  array[N1] real Treflect;
  array[N1] real Tleaf;
  array[N1] real time;
  array[N2] real Qabs;
  real step;
  real tmax;
}

transformed data {
  int T_count = 0;
  int R_count = 0;
  int E_count = 0;
  
  T_count = setSpline(step, tmax, Tair);
  R_count = setSpline(step, tmax, RH);
  E_count = setSpline(step, tmax, Treflect);
}

parameters {
  real<lower=1e-6> gbl;
  real<lower=1e-6> gsw;
  real<lower=1e-6> k;
  real<lower=1e-6> sT;
}

transformed parameters {
  array[N1] vector[1] mod;
  real LL = 0.;
  
  mod[1,1] = Tleaf[1];
  mod[2:,] = ode_bdf_tol(derivs, mod[1,], time[1], time[2:], 1e-10, 1e-10, 10000000,
                         gbl, gsw, k, Qabs, tON, dt, N2);
  
  LL += normal_lpdf(Tleaf | mod[,1], sT);
}

model {
  target += normal_lpdf(gbl | 0, 0.005);
  target += normal_lpdf(gsw | 0, 0.005);
  target += normal_lpdf(k | 700, 250);
  target += normal_lpdf(sT | 0, 0.1);
  target += LL;
}
