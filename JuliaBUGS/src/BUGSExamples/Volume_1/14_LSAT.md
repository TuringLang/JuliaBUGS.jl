# Section 6 of the Law School Aptitude Test (LSAT)

Section 6 of the Law School Aptitude Test (LSAT) is a 5-item multiple choice test; students score 1 on each item for the correct answer and 0 otherwise, giving R = 32 possible response patterns. Boch and Lieberman (1970) present data on LSAT for N = 1000 students, part of which is shown below.

| Response Pattern | Item 1 | Item 2 | Item 3 | Item 4 | Item 5 | Frequency |
|------------------|--------|--------|--------|--------|--------|-----------|
| 1                | 0      | 0      | 0      | 0      | 0      | 3         |
| 2                | 0      | 0      | 0      | 0      | 1      | 6         |
| 3                | 0      | 0      | 0      | 1      | 0      | 2         |
| .                | .      | .      | .      | .      | .      | .         |
| .                | .      | .      | .      | .      | .      | .         |
| .                | .      | .      | .      | .      | .      | .         |
| 30               | 1      | 1      | 1      | 0      | 1      | 61        |
| 31               | 1      | 1      | 1      | 1      | 0      | 28        |
| 32               | 1      | 1      | 1      | 1      | 1      | 298       |

The above data may be analysed using the one-parameter Rasch model (see Andersen (1980), pp.253-254; Boch and Aitkin (1981)). The probability $p_{jk}$ that student $j$ responds correctly to item $k$ is assumed to follow a logistic function parameterized by an 'item difficulty' or threshold parameter $a_k$ and a latent variable $q_j$ representing the student's underlying ability. The ability parameters are assumed to have a Normal distribution in the population of students. That is:

$$logit(p_{jk}) = q_j - a_k, j = 1,...,1000; k = 1,...,5$$

$$q_j \sim Normal(0, \tau)$$

The above model is equivalent to the following random effects logistic regression:

$$logit(p_{jk}) = \beta q_j - a_k, j = 1,...,1000; k = 1,...,5$$

$$q_j \sim Normal(0, 1)$$

where $\beta$ corresponds to the scale parameter ($\beta^2 = \tau$) of the latent ability distribution. We assume a half-normal distribution with small precision for $\beta$; this represents vague prior information but constrains $\beta$ to be positive. Standard vague normal priors are assumed for the $a_k$'s. Note that the location of the $a_k$'s depend upon the mean of the prior distribution for $q_j$ which we have arbitrarily fixed to be zero. Alternatively, Boch and Aitkin ensure identifiability by imposing a sum-to-zero constraint on the $a_k$'s. Hence we calculate $a_k = a_k - \bar{a}$ to enable comparision of the BUGS posterior parameter estimates with the Boch and Aitkin marginal maximum likelihood estimates.
