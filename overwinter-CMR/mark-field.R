### Mark-recapture ###

# ---- set working directory ----
setwd("C:/Users/user/Documents/Research/CHONe-1.2.1/")

# ---- load required packages ----

library(lubridate)

library(mixdist)
#library(marked)
library(tidyverse)
library(RMark)
source("./code/pulse_range_fct.R")

# ---- load data ----
data<-read.csv("./data/data-working/CMR-field-MAY-captures.csv")
fallcatch<-read.csv("./data/data-working/CMR-field-adj.csv")
subsample<-read.csv("./data/data-working/subsample_wk1-2-field.csv")
pulse0<-read.csv("./data/data-working/CMR-0pulses.csv")
pulse1<-read.csv("./data/data-working/pulse_range_age1_final.csv")
trips<-read.csv("./data/data-working/newman-trips.csv")

# ---- check data ----
names(data)
str(data)
summary(data)
head(data)

names(subsample)
str(subsample)
summary(subsample)
head(subsample)

str(trips)
# format date
data$date<-ymd(paste(data$year,data$month,data$day,sep="-"))
subsample$date<-ymd(paste(subsample$Year,subsample$Month,subsample$Day,sep="-"))

trips$date<-ymd(paste(trips$year,trips$month,trips$day,sep="-"))
fallcatch$date<-ymd(paste(fallcatch$year,fallcatch$month,fallcatch$day,sep="-"))
fallcatch<-fallcatch%>%filter(day==19 & status==1)

data<-left_join(data,trips)
                

# Pulse assignments

# set up age 1 pulses
glimpse(pulse1)
summary(pulse1)
pulse1<-pulse1%>%
  mutate(pulse=replace(pulse,pulse==3,2),
         pulse=replace(pulse,pulse==5,3))%>%
  filter(!is.na(min))
pulse.assign1<-data.frame(trip=rep(pulse1$trip,pulse1$max-pulse1$min+1),
                         year=rep(pulse1$year,pulse1$max-pulse1$min+1),
                         pulse=rep(pulse1$pulse,pulse1$max-pulse1$min+1),
                         mmSL=unlist(mapply(seq,pulse1$min,pulse1$max)))

glimpse(pulse.assign1)
pulse.assign1<-pulse.assign1%>%
  mutate(age=1)
glimpse(pulse0)
pulse0<-pulse0%>%
  mutate(year=cohort, age=0)%>%
  select(-cohort)

pulses<-bind_rows(pulse0,pulse.assign1)%>%
  rename(sl=mmSL)%>%
  filter(year>=2016)

# ----- pulse assign ----
data$site<-str_sub(data$animal_id,start = 1,end = 2)
data$id<-as.numeric(str_sub(data$animal_id,start=4))
head(data)


# assign fall fish
october.pulses<-pulses%>%
  filter(year==2016 & age==0)
fall.fish<-data%>%
  filter(id<2)

fall.pulses<-left_join(fall.fish,october.pulses)

may.pulses<-pulses%>%
  filter(year==2017 & age==1 & trip ==10)%>%
  select(-trip,-year)
spring.fish<-data%>%
  filter(id>1)

spring.pulses<-left_join(spring.fish,may.pulses)

pulse.size<-bind_rows(fall.pulses,spring.pulses)

# fill in missing pulses
fall.pulses%>%
  ggplot(aes(x=date,y=sl,colour=factor(pulse)))+geom_point()
ggplot(pulse.size,aes(x=date,y=sl,colour=factor(pulse)))+geom_point()


oct.notrip<-pulse.size%>%filter(id<2 & day == 19)%>%
  filter(!is.na(sl))
oct<-bind_rows(oct.notrip,fallcatch)%>%# include captured fish
  select(-pulse,-status)

qplot(sl,data=oct,binwidth=5)
SL<-select(oct,sl)
summarise(SL,min(sl),max(sl))
group.oct<-mixgroup(SL,breaks= c(0,seq(50,90,5),93),
                    xname=NULL,k=NULL,usecondit=FALSE)
plot(group.oct)

# ---- set initial parameters ----
par<-mixparam(c(60,80),c(5),pi=NULL)
plot(group.oct,par,"gamma")

# fit mixture
fit1<-mix(group.oct,par, dist="gamma",mixconstr(consigma = "CCV"),
          emsteps = 15, usecondit = FALSE)

summary(fit1)
plot(fit1)
plot(fit1,root=T)

par2<-mixparam(c(52,62,80),c(5),pi=NULL)
plot(group.oct,par2,"gamma")

fit2<-mix(group.oct,par2,dist="gamma",mixconstr(consigma = "CCV"),
          emsteps = 15, usecondit = FALSE)
summary(fit2)
plot(fit2)
plot(fit2,root=T)

head(oct)
notrip<-bind_cols(fit2$parameters, fit2$se)%>%
  mutate(trip=1,year=2016,month=10,day=19,cohort=2016)
notrip<-mutate(notrip,dummy_pulse=rev(seq(1:nrow(notrip))))

pulse.range<-pulse_range(notrip)

# use min and max for each pulse to then create a dataframe with all length possibilities per pulse
pulse.assign<-data.frame(trip=rep(pulse.range$trip,pulse.range$max-pulse.range$min+1),
                         cohort=rep(pulse.range$cohort,pulse.range$max-pulse.range$min+1),
                         pulse=rep(pulse.range$dummy_pulse,pulse.range$max-pulse.range$min+1),
                         sl=unlist(mapply(seq,pulse.range$min,pulse.range$max)))

pulse.assign<-pulse.assign%>%
  mutate(year=cohort)%>%
  select(-cohort,-trip,-year)

oct.notrip<-oct.notrip%>%
  select(-pulse)

pulses.notrip<-left_join(oct.notrip,pulse.assign)

# combine
# pulse.size and pulses.notrip
# take out october no trip from pulse.size, then re-add pulses.notrip

final1<-pulse.size[1:140,]
final2<-pulse.size[170:1200,]

final<-bind_rows(final1,pulses.notrip,final2)


final%>%
  filter(month!=5)%>%
  ggplot(aes(y=sl,x=date,colour=factor(pulse)))+
  geom_jitter()

 # ---- mark analysis ----

# select dat that is within popultion
# sl >55 mm and age <2

mrkdata<-final%>%
  filter(age<2)%>%
  select(date,year,month,animal_id,sl,mark,pulse)%>%
  data.frame()

# Determine time-steps
collection.dates<-distinct(mrkdata,date)
year<-2016
month<-12
day<-31
reference<-as.data.frame(cbind(year,month,day))
reference$date<-ymd(paste(reference$year,reference$month,reference$day,sep="-"))
reference<-select(reference,date)
collection.dates<-rbind(collection.dates,reference)
collection.dates$julian<-yday(collection.dates$date)
collection.dates<-mutate(collection.dates,mark.period=julian-287)
collection.dates<-collection.dates%>%
  mutate(mark.period=replace(mark.period,mark.period==-143,223))
collection.dates<-collection.dates[1:4,]
collection.dates

# ---- format for RMark ----

mrkdata1<-mrkdata%>%
  select(-year,-month,-day)

# melt then cast, equivalent to gather then spread

mrkdata2<-spread(mrkdata1,date,mark,fill=0)

mrkdata3<-unite(mrkdata2,ch,c("2016-10-14","2016-10-19","2017-05-24"),
           sep="",remove=TRUE)
View(mrkdata3)
unique(mrkdata3$ch)
str(mrkdata3)
duplicated(mrkdata3$animal_id)
cod<-mrkdata3

View(cod)

# ---- CJS Run ----
# Newbridge only
# time and dependent - no length yet
nb<-cod[str_detect(cod$animal_id,"NB"),]
nb$sl<-as.numeric(nb$sl)
nb.all<-nb%>%
  select(ch)%>%
  data.frame()
nb.processed<-process.data(nb.all,time.intervals = c(5,217))
nb.model<-function()
{
  # process data for CJS model and make default design data
  nb.processed<-process.data(nb.all,time.intervals = c(5,217))
  nb.ddl<-make.design.data(nb.processed)
  # define models for Phi
  Phi.dot<-list(formula=~1)
  Phi.time<-list(formula=~time)
  # define models for p
  p.dot<-list(formula=~1)
  p.time<-list(formula=~time)
  # create model list
  cml<-create.model.list("CJS")
  # run and return models
  return(mark.wrapper(cml,data=nb.processed,ddl=nb.ddl))

}
nb.results<-nb.model()
nb.results
#export.MARK(nb.processed,"overwinter",nb.results,replace=TRUE)
summary(nb.results[[2]])
nb.results[[2]]# deviance of 0, poor model fit, but c-hat =1 which is good model fit??
PIMS(nb.results[[1]],"Phi")
PIMS(nb.results[[1]],"p")
nb.results$model.table
nb.results[[2]]
# all four could biologically be a possibility
# may want to run bootstrap GOF analysis on each model to see
# what one to go with
release.gof(nb.processed,invisible = TRUE,title = "Release-gof",view=TRUE)


# ---- CJS survival by pulse ----
# Newbridge only
# time and dependent - no length yet
nb.pulse<-nb%>%
  select(ch,pulse)%>%
  data.frame()
unique(nb.pulse$pulse)
nb.pulse$pulse<-as.factor(nb.pulse$pulse)
str(nb.pulse)

pulse.model<-function()
{
  # process data for CJS model and make default design data
  nb.processed<-process.data(nb.pulse,time.intervals = c(5,217),
                             groups="pulse")
  nb.ddl<-make.design.data(nb.processed)
  # define models for Phi
  Phi.dot<-list(formula=~1)
  Phi.time<-list(formula=~time)
  Phi.pulse<-list(formula=~pulse)
  Phi.timepluspulse<-list(formula=~time+pulse)

  # define models for p
  p.dot<-list(formula=~1)
  p.time<-list(formula=~time)
  p.pulse<-list(formula=~pulse)
  p.timepluspulse<-list(formula=~time+pulse)
  # create model list
  cml<-create.model.list("CJS")
  # run and return models
  return(mark.wrapper(cml,data=nb.processed,ddl=nb.ddl))
}
pulse.results<-pulse.model()
nb.processed<-process.data(nb.pulse,time.intervals = c(5,217),
                           groups="pulse")
export.MARK(nb.processed,"overwinterpulse",model=NULL,replace=TRUE,ind.covariates = "all")
pulse.results
summary(pulse.results[[15]])
c.hat<-pulse.results[[15]]$results$deviance/pulse.results[[15]]$results$deviance.df
c.hat
tail(nb.pulse)

PIMS(pulse.results[[15]],"p")

release.gof(nb.processed,invisible = TRUE,title="release-gof",view=TRUE)
summary(pulse.results[[15]])
pulse.results[[15]]
pulse.results[[15]]$design.data
names(pulse.results)
round(pulse.results$Phi.timepluspulse.p.time$results$real[,1:4],3)


# ---- pulses 1:3 ----
# Take out late pulses (the ones that were not marked)
nb13<-nb.pulse%>%
  filter(pulse!=4)%>%
  as.data.frame()

early.pulse.model<-function()
{
  # process data for CJS model and make default design data
  nb.processed<-process.data(nb13,time.intervals = c(5,217),
                             groups="pulse")
  nb.ddl<-make.design.data(nb.processed)
  # define models for Phi
  Phi.dot<-list(formula=~1)
  Phi.time<-list(formula=~time)
  Phi.pulse<-list(formula=~pulse)
  Phi.timepluspulse<-list(formula=~time+pulse)
  
  # define models for p
  p.dot<-list(formula=~1)
  p.time<-list(formula=~time)
  p.pulse<-list(formula=~pulse)
  p.timepluspulse<-list(formula=~time+pulse)
  # create model list
  cml<-create.model.list("CJS")
  # run and return models
  return(mark.wrapper(cml,data=nb.processed,ddl=nb.ddl))
}
early.pulse.results<-early.pulse.model()
early.pulse.results
adjust.chat(3.32,early.pulse.results)
adjust.chat(0.80,early.pulse.results)
nb.processed<-process.data(nb13,time.intervals = c(5,217),
                           groups="pulse")
summary(early.pulse.results[[15]])
c.hat<-early.pulse.results[[15]]$results$deviance/early.pulse.results[[15]]$results$deviance.df
c.hat
tail(nb.pulse)

PIMS(early.pulse.results[[15]],"p")

release.gof(nb.processed,invisible = TRUE,title="release-gof",view=TRUE)
summary(pulse.results[[15]])
pulse.results[[15]]
pulse.results[[15]]$design.data
names(early.pulse.results)
round(early.pulse.results$Phi.timepluspulse.p.time$results$real[,1:4],4)

cleanup(ask=FALSE)

# ---- simulation ----
# start with basic model first (one group)
n.occasions<-3
marked<-rep(500,n.occasions-1)
phi<-rep(0.99,n.occasions-1)
p<-runif(n.occasions-1,0.007,1)


simul.cjs<-function(phi,p,marked)
{
  n.occasions<-length(p)+1
  Phi<-matrix(phi,n.occasions-1,nrow=sum(marked),byrow=T)
  P<-matrix(p,n.occasions-1,nrow=sum(marked),byrow=T)
  
  #n.occasions<-dim(Phi)[2]+1
  CH<-matrix(0,ncol=n.occasions,nrow=sum(marked))
  #define a vector with marking occasion
  mark.occ<-rep(1:length(marked),marked[1:length(marked)])
  #fill in CH
  for (i in 1:sum(marked))
  {
    CH[i,mark.occ[i]]<-1
    if (mark.occ[i]==n.occasions) next
    for(t in (mark.occ[i]+1):n.occasions)
    {
      #survive?
      sur<-rbinom(1,1,Phi[i,t-1])
      if(sur==0) break #move to next
      #recaptured?
      rp<-rbinom(1,1,P[i,t-1])
      if(rp==1) CH[i,t]<-1
    } #t
  } #i
  return(CH)
}

sim<-simul.cjs(phi,p,marked)

pasty<-function(x) 
{
  k<-ncol(x)
  n<-nrow(x)
  out<-array(dim=n)
  for (i in 1:n)
  {
    out[i]<-paste(x[i,],collapse="")
  }
  return(out)
}
sim.data<-data.frame(ch=pasty(sim))

sim.processed=process.data(sim.data,model="CJS")
sim.ddl=make.design.data(sim.processed)

#time only
Phi=list(formula=~1)
p.t=list(formula=~time)
#global.est<-mark(sim.processed,sim.ddl,model.parameters=list(Phi=Phi.sex.T,p=p.sex.T),output=F,silent=T)
time.est<-mark(sim.processed,sim.ddl,model.parameters=list(Phi=Phi,p=p.t),output=F,silent=T)
null.est<-mark(sim.processed,sim.ddl,output=F,silent=T)


summary(global.est)
summary(time.est)
summary(null.est)

results<-collect.models()
results