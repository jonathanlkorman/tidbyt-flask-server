# HELPER: lirr_helper

load("encoding/json.star", "json")
load("render.star", "render")
load("schema.star", "schema")

CORE_BACKGROUND_COLOR = "#4D5357"
CORE_TEXT_COLOR = "#FFFFFF"

def main(config):
    helper_data = json.decode(config.str("helper_data", {}))   
    trains_data = json.decode(helper_data.get("trains", []))
    
    if type(trains_data) == "list":
        if len(trains_data) == 0:
            return render.Root(
                child = render.Marquee(
                    width = 64,
                    child = render.Text("No trains found"),
                    offset_start = 5,
                    offset_end = 32,
                )
            )
        elif len(trains_data) == 1:
            return render.Root(child = renderTrain(trains_data[0]))
        else:
            return render.Root(
                child = render.Column(
                    children = [
                        renderTrain(trains_data[0]),
                        render.Box(
                            color = "#ffffff",
                            width = 64,
                            height = 1,
                        ),
                        renderTrain(trains_data[1]),
                    ],
                )
            )
    else:
        # If it's not a list, assume it's a single train
        return render.Root(child = renderTrain(trains_data))

def renderTrain(train):
    destination = train.get("destination_station_name", "Unknown")
    line = train.get("route_name", "Unknown")
    textColor = "#" + train.get("route_text_color", "FFFFFF")
    backgroundColor = "#" + train.get("route_color", "000000")
    time = train.get("departure_time", "N/A")

    return render.Row(
        expanded = True,
        main_align = "space_between",
        cross_align = "end",
        children = [
            render.Padding(
                pad = 2,
                child = render.Box(
                    width = 10,
                    height = 10,
                    color = backgroundColor,
                    child = render.Text(
                        color = textColor,
                        content = line[0] if destination else "?",
                    ),
                ),
            ),
            render.Column(
                children = [
                    render.Marquee(
                        width = 64 - 16,
                        child = render.Text(
                            content = destination.upper(),
                        ),
                    ),
                    render.Text(
                        content = time,
                        color = "#ff9900",
                    ),
                ],
            )
        ],
    )

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "station",
                name = "Station",
                desc = "The station to get train times for",
                icon = "trainSubway",
            ),
        ],
    )