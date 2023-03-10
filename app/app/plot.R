library(magrittr)
library(ggplot2)

name_mapper <- list(
  "tas"="Temperature",
  "tasmin" = "Minimum Temperature",
  "tasmax" = "Maximum Temperature",
  "sfcWind" = "Wind Speed",
  "pr" = "Precipitation",
  "rsds" = "Short Wave Radiation", 
  "rlds" = "Long Wave Radiation",
  "hurs" = "Relative Humidity",
  "penman" = "Potential ET"
)

orig_units <- list(
  "hurs" = "percent",
  "pr" = "mm",
  "rsds" = "W m-2",
  "rlds" = "W m-2",
  "sfcWind" = "m/s",
  "tas" = "kelvin",
  "tasmax" = "kelvin", 
  "tasmin" = "kelvin",
  "penman" = "mm"
)

units_us <- list(
  "hurs" = "percent",
  "pr" = "in",
  "rsds" = "W m-2",
  "rlds" = "W m-2",
  "sfcWind" = "mi/hr",
  "tas" = "degF",
  "tasmax" = "degF", 
  "tasmin" = "degF",
  "penman" = "in"
)

units_metric <- list(
  "hurs" = "percent",
  "pr" = "cm",
  "rsds" = "W m-2",
  "rlds" = "W m-2",
  "sfcWind" = "m/s",
  "tas" = "degC",
  "tasmax" = "degC", 
  "tasmin" = "degC"
)

colors = 
  c("Historical Emissions" = rgb(0,0,0,
                                 maxColorValue = 255),
    "transparent",
    " "  = "transparent",
    "  "  = "transparent",
    "Moderating Emissions\n(SSP1-2.6)" = rgb(34,46,77,
                                            maxColorValue = 255),
    "Middle of the Road\n(SSP2-4.5)" = rgb(223,146,71,
                                          maxColorValue = 255),
    "High Emissions\n(SSP3-7.0)" = rgb(187,54,51,
                                      maxColorValue = 255),
    "Accelerating Emissions\n(SSP5-8.5)" = rgb(122,41,40,
                                              maxColorValue = 255)
    
  )

factor_scenario <- function(dat) {
  dplyr::mutate(
    dat, 
    scenario = dplyr::recode(
      scenario, 
      "historical" = "Historical Emissions",
      "ssp126" = "Moderating Emissions\n(SSP1-2.6)",
      "ssp245" = "Middle of the Road\n(SSP2-4.5)",
      "ssp370" = "High Emissions\n(SSP3-7.0)",
      "ssp585" = "Accelerating Emissions\n(SSP5-8.5)"
    ) %>% 
      factor(
        levels = c("Historical Emissions",
                   "Moderating Emissions\n(SSP1-2.6)",
                   "Middle of the Road\n(SSP2-4.5)",
                   "High Emissions\n(SSP3-7.0)",
                   "Accelerating Emissions\n(SSP5-8.5)")
      )
  )
}

build_titles <- function(location, variable, us_units, monthly = FALSE) {
  
  if (us_units) {
    unit <- units_us[[variable]]
  } else {
    unit <- units_metric[[variable]]
  }
  
  if (monthly) {
    pretext <- "Monthly Climate Projections"
  } else {
    pretext <- "Climate Projections"
  }
  
  list(
    "y" = glue::glue("{name_mapper[[variable]]} [{unit}]"),
    "title" = glue::glue("{pretext} of\n{name_mapper[[variable]]} for {location}")
  )
}

convert_units <- function(dat, variable, us_units) {
  
  dat %>%
      dplyr::mutate(
        value = units::set_units(value, !!orig_units[[variable]]),
        value = units::set_units(value, !!units_metric[[variable]])
      ) %>% 
      {
        if (us_units) {
          dplyr::mutate(
            ., value = units::set_units(value, !!units_us[[variable]]) %>% 
              units::drop_units()
          )
        } else {
          units::drop_units(.)
        }
      } 
}

prep_for_timeseries <- function(dat, location, v, us_units) {

  dat %>% 
    dplyr::filter(id == location, variable == v) %>% 
    dplyr::group_by(year=lubridate::year(date), scenario, model) %>% 
    dplyr::summarise(
      value = ifelse(v %in% c("pr", "penman", "hargreaves"), sum(value), mean(value)), 
      .groups = "drop"
    ) %>% 
    dplyr::collect() %>%
    convert_units(v, TRUE) %>%
    dplyr::group_by(year, scenario) %>% 
    dplyr::summarise(
      upper = quantile(value, 0.9) %>% as.numeric(),
      lower = quantile(value, 0.1) %>% as.numeric(),
      value = median(value),
      .groups = "drop"
    ) %>% 
    factor_scenario()
  
}

make_timeseries_plot <- function(dat, location = "Beaverhead County", variable = "tas", us_units=TRUE) {
  loc <- dat %>% 
    dplyr::filter(id == location) %>% 
    head(1) %>% 
    dplyr::collect() %>% 
    dplyr::pull(name)
  
  to_plot <- prep_for_timeseries(dat, location, variable, us_units)
  titles <- build_titles(loc, variable, us_units)
    
  ggplot(to_plot, aes(x=year, color=scenario, fill=scenario)) +
      geom_line(aes(y=value)) + 
      geom_ribbon(aes(ymin=lower, ymax = upper),                
                  color = NA,
                  alpha = 0.5,
                  linewidth = 0.25) +
      scale_x_continuous(expand = c(0,0),
                         breaks = seq(1950,2100,25),
                         limits = c(1950,2100)) +
      labs(x = NULL,
           y = titles[["y"]],
           title = titles[["title"]] 
           ) +
      theme_minimal(14) +
      scale_color_manual(values = colors) +
      scale_fill_manual(values = colors) +
      theme(
        legend.title = element_blank(),
        # legend.justification = c(1, 1),
        legend.position = "bottom",
        legend.key.width = unit(0.25,"in"),
        axis.title.y = element_text(margin = margin(t = 0, r = 10, b = 0, l = 0)),
        plot.margin=unit(c(0.1,0.2,0.1,0.1), "in")
      ) +
      ggplot2::guides(colour = guide_legend(ncol = 2)) +
      coord_cartesian(clip = "off")
}

prep_for_monthly_plot <- function(dat, location, v = "tas", us_units = T) {
    
  out <- dat %>% 
    dplyr::filter(id == location, variable == v) %>% 
    dplyr::collect() %>%
    dplyr::mutate(
      year = lubridate::year(date), 
      month = month.name[lubridate::month(date)],
      grp = dplyr::case_when(
        year %in% 1991:2020 ~ "Reference Period (1991-2020)", 
        year %in% 2040:2069 ~ "Mid Century (2040-2069)",
        year %in% 2970:2099 ~ "End-of-Century (2070-2099)"
      ), 
      scenario = ifelse(year >= 2015 & year <= 2020, "historical", scenario)
    )  %>% 
    dplyr::filter(!is.na(grp)) %>% 
    convert_units(v, us_units) %>% 
    dplyr::group_by(scenario, month, grp) %>% 
    dplyr::summarise(
      upper = quantile(value, 0.9) %>% as.numeric(),
      lower = quantile(value, 0.1) %>% as.numeric(),
      value = median(value),
      .groups = "drop"
    ) 
  
  filt <- out %>% 
    dplyr::filter(scenario == "historical") 
  
  dplyr::bind_rows(
    dplyr::mutate(filt, grp = "Mid Century (2040-2069)"),
    dplyr::mutate(filt, grp = "End-of-Century (2070-2099)"),
    dplyr::filter(out, scenario != "historical")
  ) %>% 
    dplyr::mutate(
      month = factor(month, levels = month.name),
      grp = factor(grp, levels = c(
        "Reference Period (1991-2020)",
        "Mid Century (2040-2069)",
        "End-of-Century (2070-2099)")
      )
    ) %>% 
    factor_scenario()
}

make_monthly_plot <- function(dat, location, variable, us_units) {
  loc <- dat %>% 
    dplyr::filter(id == location) %>% 
    head(1) %>% 
    dplyr::collect() %>% 
    dplyr::pull(name)

  to_plot <- prep_for_monthly_plot(dat, location, variable, us_units) 
  titles <- build_titles(loc, variable, us_units, monthly = T)
  
  to_plot %>%
    ggplot(aes(x=month, color=scenario)) + 
      geom_pointrange(aes(y=value, ymin=lower, ymax=upper), position = position_dodge(width=0.25)) + 
      geom_line(aes(y=value, group=scenario)) +
      facet_grid(rows="grp") +
      labs(x = NULL,
           y = titles[["y"]],
           title = titles[["title"]]
      ) +
    theme_minimal(14) +
    scale_color_manual(values = colors) +
    scale_fill_manual(values = colors) +
    theme(
      legend.title = element_blank(),
      # legend.justification = c(1, 1),
      legend.position = "bottom",
      legend.key.width = unit(0.25,"in"),
      axis.title.y = element_text(margin = margin(t = 0, r = 10, b = 0, l = 0)),
      plot.margin=unit(c(0.1,0.2,0.1,0.1), "in")
    ) +
    ggplot2::guides(colour = guide_legend(ncol = 2)) +
    coord_cartesian(clip = "off")
}

placeholder_graph <- function() {
  
  tibble::tibble(x=1, y=1, txt="Click a county to plot data!") %>% 
    ggplot(aes(x=x, y=y)) + 
      geom_text(aes(label=txt), size=10) + 
      theme_minimal() +
      theme(
        axis.ticks = element_blank(),
        axis.text = element_blank(),
        axis.title = element_blank()
      )
}
