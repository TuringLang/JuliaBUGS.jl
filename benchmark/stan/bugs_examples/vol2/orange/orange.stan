// Orange Trees 
// http://www.openbugs.net/Examples/Otrees.html

// status: error thrown out during execution immediately 

data {
  int<lower=0> K;
  int<lower=0> N;
  array[N] int x;
  array[K, N] real Y;
}
parameters {
  real<lower=0> tau_C;
  array[K, 3] real theta;
  array[3] real mu;
  array[3] real<lower=0> tau;
}
transformed parameters {
  array[K, 3] real phi;
  array[3] real sigma;
  real sigma_C;
  for (k in 1 : K) {
    phi[k, 1] = exp(theta[k, 1]);
    phi[k, 2] = exp(theta[k, 2]) - 1;
    phi[k, 3] = -exp(theta[k, 3]);
  }
  for (j in 1 : 3) {
    sigma[j] = 1 / sqrt(tau[j]);
  }
  sigma_C = 1 / sqrt(tau_C);
}
model {
  tau_C ~ gamma(0.001, 0.001);
  mu ~ normal(0, 100);
  for (j in 1 : 3) {
    tau[j] ~ gamma(.001, .001);
  }
  for (k in 1 : K) {
    array[N] real m;
    theta[k] ~ normal(mu, sigma);
    for (n in 1 : N) {
      m[n] = phi[k, 1] / (1 + phi[k, 2] * exp(phi[k, 3] * x[n]));
    }
    Y[k] ~ normal(m, sigma_C);
  }
}
