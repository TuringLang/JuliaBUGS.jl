
data {
  int<lower=1> N;
  int<lower=1> T;
  real xbar;
  array[T] real x;
  array[N, T] real Y;
}

parameters {
  real<lower=0> tau_c;
  real alpha_c;
  real<lower=0> alpha_tau;
  real beta_c;
  real<lower=0> beta_tau;
  array[N] real alpha;
  array[N] real beta;
}

transformed parameters {
  real sigma;
  real alpha0;
  array[N, T] real mu;
  for (i in 1:N) {
    for (j in 1:T) {
      mu[i,j] = alpha[i] + beta[i] * (x[j] - xbar);
    }
  }
  sigma = 1 / sqrt(tau_c);
  alpha0 = alpha_c - xbar * beta_c;
}

model {
  for (i in 1:N) {
    for (j in 1:T) {
      Y[i,j] ~ normal(mu[i,j], 1.0 / sqrt(tau_c));
    }
    alpha[i] ~ normal(alpha_c, 1.0 / sqrt(alpha_tau));
    beta[i] ~ normal(beta_c, 1.0 / sqrt(beta_tau));
  }
  tau_c ~ gamma(0.001, 0.001);
  alpha_c ~ normal(0.0, 1.0 / sqrt(1.0E-6));
  alpha_tau ~ gamma(0.001, 0.001);
  beta_c ~ normal(0.0, 1.0 / sqrt(1.0E-6));
  beta_tau ~ gamma(0.001, 0.001);
}
