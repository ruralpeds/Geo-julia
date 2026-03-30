# src/landscan.jl
# LandScan population dataset information and access guidance.

"""
    landscan_info() -> String

Return information about the LandScan ambient population dataset and
how to obtain it programmatically.

LandScan (produced by Oak Ridge National Laboratory) requires registration
at https://landscan.ornl.gov — it cannot be downloaded anonymously.
This function provides guidance on obtaining the data and loading it
after manual download.
"""
function landscan_info()::String
    return """
    LandScan Population Dataset
    ===========================
    Producer: Oak Ridge National Laboratory (ORNL)
    URL: https://landscan.ornl.gov
    License: Requires free registration and agreement to terms of use.

    LandScan provides ambient population estimates at approximately 1 km
    resolution (30 arc-second), representing 24-hour average ("ambient")
    population — useful for healthcare access analysis because it reflects
    where people actually spend time, not just where they sleep.

    After registration and download:
    1. Download the GeoTIFF for your year of interest
    2. Place it in: $(joinpath(DATA_DIR, "landscan"))
    3. Load with Rasters.jl:

       using Rasters
       pop = Raster("$(joinpath(DATA_DIR, "landscan", "landscan_usa_2022.tif"))")

    For zonal statistics (population per county):
       using PopulationData
       pop_counts = pop_by_polygon("path/to/landscan.tif", counties_df)
    """
end
