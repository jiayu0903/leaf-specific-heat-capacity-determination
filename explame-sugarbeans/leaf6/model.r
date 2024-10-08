library(ggplot2)
library(cowplot)
library(cmdstanr)
library(posterior)
library(bayesplot)
library(readxl)
color_scheme_set("brightblue")

theme_set(theme_cowplot())

###
#
# Warning: this model is only for a transpiring leaf !
#
###

# Directory of the data
dr <- "./sugarbeans-0315-leaf6/"
date <- "2023-03-15"
time <- "20:28:00"

# Start time of the temperature records
t0 <- as.POSIXct(paste(date, time), format="%Y-%m-%d %H:%M:%OS")

# Time points when the light was switched on
tON <- c("20:28:00")


# Observed vs. estimated light intensity (same units)
PAR <- c(257.9754468)

# Read and process air temperature data
dA <- read.csv(paste0(dr, "AirT.csv"))
dA$time <- as.POSIXct(paste(date, dA$Time), format="%Y-%m-%d %I:%M:%OS %p")
ggplot(dA, aes(x=time, y=Temperature)) + geom_point()
ggplot(dA, aes(x=time, y=Humidity)) + geom_point()

# Read and process leaf temperature data
dL <- read.csv(paste0(dr, "LeafT.csv"))
names(dL) <- c("Date", "Time", "Temperature", "Tair","Treflect")

# Parse date string
dL$ts <- as.POSIXct(paste(date, dL$Date), format="%Y-%m-%d %I:%M:%OS %p")
ggplot(dL, aes(x=ts, y=Temperature)) + geom_point()
ggplot(dL, aes(x=ts, y=Tair)) + geom_point()

# Find initial time common to both data sets
dA$time <- as.numeric(dA$time - t0)
dL$time <- dL$Time + as.numeric(dL$ts[1] - t0)

dA <- subset(dA, time >= 0)
dL <- subset(dL, time >= 0)

# Use splines to extract data at common time points
spl_A <- splinefun(dA$time, dA$Temperature)
spl_R <- splinefun(dA$time, dA$Humidity)
spl_L <- splinefun(dL$time, dL$Temperature)
spl_A2 <- splinefun(dL$time, dL$Tair)
spl_E <- splinefun(dL$time, dL$Treflect)

fitt <- smooth.spline(dA$time, dA$Humidity, cv=TRUE)
fitt2 <- smooth.spline(dA$time, dA$Temperature, cv=TRUE)
fitt3 <- smooth.spline(dL$time, dL$Tair, cv=TRUE)
fitt4 <- smooth.spline(dL$time, dL$Treflect, cv=TRUE)

fitt$df
fitt2$df
fitt3$df
fitt4$df

# Remove high frequency fluctuations
sspl_R <- smooth.spline(dA$time, dA$Humidity, df=22)
sspl_A <- smooth.spline(dA$time, dA$Temperature, df=2)
sspl_A2 <- smooth.spline(dL$time, dL$Tair, df=143)
sspl_E <- smooth.spline(dL$time, dL$Treflect, df=129)
# Check spline function
plot(Humidity~time, dA, pch=16)
points(predict(sspl_R, time)$y~time, dA, lty=2, lwd=2, col="red")

plot(Temperature~time, dA, pch=16)
lines(predict(sspl_A, time)$y~time, dA, lty=2, lwd=2, col="red")

plot(Tair~time, dL, pch=16)
lines(predict(sspl_A2, time)$y~time, dL, lty=2, lwd=2, col="red")

# New time points
time <- subset(dL, time < max(dA$time))$time

# Merge the data sets
d <- data.frame(time=time, Ta=predict(sspl_A, time)$y,
                Ta2=predict(sspl_A2, time)$y,
                Treflect=predict(sspl_E, time)$y,
                Tl=spl_L(time),
                RH=predict(sspl_R, time)$y)

# Correct for offset between Rotronic sensor and thermal camera temperature
#d$Tl <- d$Tl - (tail(d$Tl) - tail(d$Ta))

ggplot(d, aes(x=time)) + geom_point(aes(y=Ta)) +
  geom_point(aes(y=Ta2), col="blue") +
  geom_point(aes(y=Tl), col="red") + geom_point(aes(y=Treflect), col="green") +ylab("Temperature")
ggplot(d, aes(x=time, y=Tl - Ta)) + geom_point() + ylab("Tl - Ta")


# Function to be passed to the ODE solver
l <- NULL
l$N1 <- nrow(d)

# Time light was turned ON
l$tON <- paste(date, tON)
l$tON <- as.POSIXct(l$tON, format="%Y-%m-%d %H:%M:%OS")
l$tON <- as.numeric(l$tON - t0, units="secs")
l$N2 <- length(l$tON)
l$Qabs <- PAR

l$ts <- diff(c(0, l$tON, max(d$time)))
l$N3 <- length(l$ts)
l$dt <- rep(10, length(l$tON))
l$N4 <- length(l$dt)

l$Tair <- d$Ta
l$RH <- d$RH / 100
l$Treflect <- d$Treflect
l$Tleaf <- d$Tl
l$time <- d$time
l$step <- 0.1
l$tmax <- max(d$time)

###
# Generate initial parameter values
##
init <- function()
{
  list(gbl=runif(1,0.01,0.03),
       gsw=runif(1,0.001,0.003),
       k=runif(1,600,900),
       sT=runif(1,0.2,0.3))
}

# Compile the bayesian model
file <- file.path(getwd(), "model.stan")
header <- file.path(getwd(), "user_header.hpp")
mod <- cmdstan_model(file,
                     cpp_options=list(USER_HEADER=header),
                     stanc_options = list("allow-undefined"))

# Fit the model to observed data
fit <- mod$sample(
  data = l,
  chains = 4,
  parallel_chains = 4,
  refresh = 10,
  init=init,
  iter_warmup = 500,
  iter_sampling = 500,
  adapt_delta=0.7,
  save_warmup = T,
  output_dir=getwd(),
  metric = "dense_e",
  step_size=0.0001
)

# See if the model converged properly
fit$cmdstan_diagnose()
fit$save_object(file = "fit.RDS")
fit <- readRDS("fit.RDS")

# Diagnostic graphs
np <- names(init())
fs <- fit$summary(np)
mcmc_hist(fit$draws(np))
mcmc_trace(fit$draws(np), n_warmup=500)
mcmc_pairs(fit$draws(np))

fs


write.table(Tl_mod, "Temperature.csv", row.names=F, col.names=F, sep=",")
write.table(d$Tl, "Temperature-Obs.csv", row.names=F, col.names=F, sep=",")

