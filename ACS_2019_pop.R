library(data.table)

.args <- if (interactive()) c(
  "ACS_2019_pop_data.csv",
  file.path("process", "ACS_2019_pop.rds")
) else commandArgs(trailingOnly = TRUE)

#' locations that are included in the analysis
locs_of_interest <- c("FL", "VT", "MS")

#' read in population data, empirical vaccination data
pop.in <- fread(.args[1], header = TRUE)

#' function to calculate the correct age bin populations
extract_bins <- function(SD) {
  SD[,
     .(pop = c(
       `5_14` + `15_17` + `18_120`,
       `5_9` + (2/5)*`10_14`,
       `5_14` + `15_17` - `5_9`,
       `18_120` - `65_120`,
       `65_120`),
       bin_min = c(5,5,12,18,65),
       bin_max = c(120, 11, 17, 64, 120)
     )
  ]
}

#' generate long-form population data.table and calculate age bin population proportions
pop.dt <- pop.in[location %in% locs_of_interest, extract_bins(.SD), by=location]
pop.dt[, prop := pop/pop[(bin_min == 5) & (bin_max == 120)], by=location]

saveRDS(pop.dt, tail(.args, 1))
