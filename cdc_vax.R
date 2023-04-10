library(data.table)

.args <- if (interactive()) c(
  "cdc_covid-19_vax_data.csv",
  file.path("process", "ACS_2019_pop.rds"),
  file.path("process", "cdc_vax.rds")
) else commandArgs(trailingOnly = TRUE)

#' locations that are included in the analysis
locs_of_interest <- c("FL", "VT", "MS")

cdc.in <- fread(.args[1])
cdc.in[, Date := as.Date(Date, "%m/%d/%Y") ]

pop.dt <- readRDS(.args[2])

#' function to roll negative values over to the next day to address errors in cumulative data
rollneg <- function(v) {
  for (i in 1:(length(v) - 1)) {
    if (v[i] < 0) {
      n_to_decrement = v[i]
      v[i] = 0
      v[i+1] = v[i+1] + n_to_decrement
    }
  }
  return(as.numeric(v))
}

#' master function to process vaccination administration data
MASTERFUN <- function(SD) {
  #' subset CDC data to isolate necessary columns and fill NA values with 0
  sub_d = SD[Recip_Administered > 0 & Administered_Dose1_Recip_65Plus != 0,
             .(date = Date,
               Administered_Dose1_Recip_5Plus, Administered_Dose1_Recip_12Plus, Administered_Dose1_Recip_18Plus, Administered_Dose1_Recip_65Plus,
               Series_Complete_5Plus, Series_Complete_12Plus, Series_Complete_18Plus, Series_Complete_65Plus,
               Additional_Doses_12Plus, Additional_Doses_18Plus, Additional_Doses_65Plus)]
  sub_d = setnafill(x = sub_d, fill = 0, cols = colnames(sub_d)[2:ncol(sub_d)])

  #' because CDC data is reported using nested age bins, an adjustment is necessary for proper processing
  #' larger age bins may have 0s reported, but the following lines ensure that larger age bins have values that are at least equal to nested values
  sub_d[Administered_Dose1_Recip_18Plus == 0, Administered_Dose1_Recip_18Plus := Administered_Dose1_Recip_65Plus]
  sub_d[Administered_Dose1_Recip_12Plus == 0, Administered_Dose1_Recip_12Plus := Administered_Dose1_Recip_18Plus]
  sub_d[Administered_Dose1_Recip_5Plus == 0, Administered_Dose1_Recip_5Plus := Administered_Dose1_Recip_12Plus]

  sub_d[Series_Complete_18Plus == 0, Series_Complete_18Plus := Series_Complete_65Plus]
  sub_d[Series_Complete_12Plus == 0, Series_Complete_12Plus := Series_Complete_18Plus]
  sub_d[Series_Complete_5Plus == 0, Series_Complete_5Plus := Series_Complete_12Plus]

  sub_d[Additional_Doses_18Plus == 0, Additional_Doses_18Plus := Additional_Doses_65Plus]
  sub_d[Additional_Doses_12Plus == 0, Additional_Doses_12Plus := Additional_Doses_18Plus]

  #' this block address multiple processing steps
  #' nested to bounded age bins
  #' wide to long transformation
  #' cumulative to daily diffs (with the first value appended to ensure that total sum is maintained)
  #' apply rollneg function to ensure data is properly cumulative
  diff.dt <- melt(sub_d[, .(
    date,
    cumul_65_120_dose_1 = Administered_Dose1_Recip_65Plus,
    cumul_18_64_dose_1 = Administered_Dose1_Recip_18Plus - Administered_Dose1_Recip_65Plus,
    cumul_12_17_dose_1 = Administered_Dose1_Recip_12Plus - Administered_Dose1_Recip_18Plus,
    cumul_5_11_dose_1 = Administered_Dose1_Recip_5Plus - Administered_Dose1_Recip_12Plus,

    cumul_65_120_dose_2 = Series_Complete_65Plus,
    cumul_18_64_dose_2 = Series_Complete_18Plus - Series_Complete_65Plus,
    cumul_12_17_dose_2 = Series_Complete_12Plus - Series_Complete_18Plus,
    cumul_5_11_dose_2 = Series_Complete_5Plus - Series_Complete_12Plus,

    cumul_65_120_dose_3 = Additional_Doses_65Plus,
    cumul_18_64_dose_3 = Additional_Doses_18Plus - Additional_Doses_65Plus,
    cumul_12_17_dose_3 = Additional_Doses_12Plus - Additional_Doses_18Plus
  )], id.vars = "date")[
    order(date),
    .(date, value = c(value[1], diff(value))), by=.(variable = gsub("cumul_","daily_", variable))
  ][,
    .(date, value = rollneg(value)), by=variable
  ]
  return(diff.dt)
}

#' apply MASTERFUN to each location and clean up any remaining negative values at the end of the resulting TS
cdc.extract <- cdc.in[Location %in% locs_of_interest, MASTERFUN(.SD), by=.(location = Location)]
cdc.extract[date == max(date), value := ifelse(value < 0, 0, value)]

#' extract necessary columns from the variable column
cdc.extract[, c("bin_min", "bin_max", "dose") := tstrsplit(variable, "_", keep=c(2,3,5))]

#' join pop.dt to cdc.extract to calculate necessary proportions by empirical location
#' bin_prop: % of that age bin vaxd that day
#' tot_prop: % of total pop vaxd that day
dt <- cdc.extract[, .(location, date, bin_min=as.integer(bin_min), bin_max=as.integer(bin_max), dose=as.integer(dose), value)][
  order(location, date)][
    pop.dt, on=.(location, bin_min, bin_max)]
dt[, bin_prop := value / pop]
dt[, tot_prop := value / pop[bin_min == 5 & bin_max == 120], by=location]

dt <- dt[!is.na(value)]
dt[, c("pop", "prop") := NULL]

saveRDS(dt, tail(.args, 1))
