library(data.table)

#' ACS_2019_pop_data.csv available in active vac dir
#' cdc_covid-19_vax_data.csv available from the download_cdc_covid_vax_data.sh script
#' United_States_COVID-19_Cases_and_Deaths_by_State_over_Time.csv available from https://data.cdc.gov/Case-Surveillance/United-States-COVID-19-Cases-and-Deaths-by-State-o/9mfq-cb36
#' COVID-19_Reported_Patient_Impact_and_Hospital_Capacity_by_State_Timeseries.csv available from https://healthdata.gov/Hospital/COVID-19-Reported-Patient-Impact-and-Hospital-Capa/g62h-syeh/data
.args <- if (interactive()) c(
  "United_States_COVID-19_Cases_and_Deaths_by_State_over_Time.csv",
  "COVID-19_Reported_Patient_Impact_and_Hospital_Capacity_by_State_Timeseries.csv",
  file.path("process", "ACS_2019_pop.rds"),
  file.path("process", "us_outcomes.rds")
) else commandArgs(trailingOnly = TRUE)

#' locations that are included in the analysis
locs_of_interest <- c("FL", "VT", "MS")

dths.in <- fread(.args[1])[state %in% locs_of_interest]
dths.in[, date := as.Date(submission_date, format = "%m/%d/%Y")]

hosp.in <- fread(.args[2])[state %in% locs_of_interest]
hosp.in[, date := as.Date(date, format = "%Y/%m/%d")]

pop.dt <- readRDS(.args[3])

adj_dths <- dths.in[, .(date, state, tot_death)][
  pop.dt[bin_min == 5 & bin_max == 120, .(location, pop)],
  on = .(state==location)
][, tot_dth_p10k := tot_death * (1e4/pop) ][
    order(state, date), .(
      state, date, outcome = "death",
      cinc = tot_death, cinc_p10k = tot_dth_p10k
)]


adj_hosp <- hosp.in[
  is.finite(previous_day_admission_adult_covid_confirmed) |
  is.finite(previous_day_admission_pediatric_covid_confirmed),
  .(date, state, hosp_inc = previous_day_admission_adult_covid_confirmed + previous_day_admission_pediatric_covid_confirmed)
][
  pop.dt[bin_min == 5 & bin_max == 120, .(location, pop)],
  on = .(state==location)
][, hosp_inc_p10k := hosp_inc * (1e4/pop) ][
  order(date), .(
  date, outcome = "hosp",
  cinc = cumsum(hosp_inc),
  cinc_p10k = cumsum(hosp_inc_p10k)
), by = .(state)
]

dt <- setkey(rbind(adj_dths, adj_hosp), state, outcome, date)

saveRDS(dt, tail(.args, 1))
