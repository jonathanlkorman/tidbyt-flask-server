load("encoding/json.star", "json")
load("encoding/base64.star", "base64")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
load("time.star", "time")

CACHE_TTL_SECONDS = 300
NYC_PORTAL_URL = "https://portal.311.nyc.gov/home-cal"
DEFAULT_TIMEZONE = "America/New_York"
DEFAULT_LOCATION = """
{
    "lat": "40.6781784",
    "lng": "-73.9441579",
    "description": "Brooklyn, NY, USA",
    "locality": "Brooklyn",
    "place_id": "ChIJCSF8lBZEwokRhngABHRcdoI",
    "timezone": "America/New_York"
}
"""
WHITE = "#FFFFFF"
BLACK = "#000000"
RED = "#FF0000"

ASP_LOGO = base64.decode("""
PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiPz4KPCEtLSBHZW5lcmF0b3I6IEFkb2JlIElsbHVzdHJhdG9yIDIyLjAuMSw
gU1ZHIEV4cG9ydCBQbHVnLUluIC4gU1ZHIFZlcnNpb246IDYuMDAgQnVpbGQgMCkgIC0tPgo8c3ZnIHZlcnNpb249IjEuMSIgaWQ9IkxheW
VyXzEiIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgeG1sbnM6eGxpbms9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkveGxpb
msiIHg9IjBweCIgeT0iMHB4IgoJIHZpZXdCb3g9IjAgMCAxMjAgMTIwIiBzdHlsZT0iZW5hYmxlLWJhY2tncm91bmQ6bmV3IDAgMCAxMjAg
MTIwOyIgeG1sOnNwYWNlPSJwcmVzZXJ2ZSI+CjxzdHlsZSB0eXBlPSJ0ZXh0L2NzcyI+Cgkuc3Qwe2ZpbGw6I0ZGRkZGRjt9Cgkuc3Qxe2Z
pbGw6I0MyMTMwMDt9Cgkuc3Qye2ZpbGw6bm9uZTtzdHJva2U6I0MyMTMwMDtzdHJva2Utd2lkdGg6NjtzdHJva2UtbGluZWNhcDpyb3VuZD
tzdHJva2UtbWl0ZXJsaW1pdDoxMDt9Cjwvc3R5bGU+CjxjaXJjbGUgY2xhc3M9InN0MCIgY3g9IjYwIiBjeT0iNjAiIHI9IjU0LjUiLz4KP
Gc+Cgk8Zz4KCQk8Zz4KCQkJPHBhdGggY2xhc3M9InN0MSIgZD0iTTU5LjksMC4xYy0zMy4xLDAtNjAsMjYuOS02MCw2MHMyNi45LDYwLDYw
LDYwczYwLTI2LjksNjAtNjBTOTMsMC4xLDU5LjksMC4xeiBNNTkuOSwxMTAuMQoJCQkJYy0yNy42LDAtNTAtMjIuNC01MC01MHMyMi40LTU
wLDUwLTUwczUwLDIyLjQsNTAsNTBTODcuNSwxMTAuMSw1OS45LDExMC4xeiIvPgoJCQk8Zz4KCQkJCTxwYXRoIGNsYXNzPSJzdDEiIGQ9Ik
04Mi45LDY1LjljLTMuNSwyLjktOC42LDQuNC0xNS4xLDQuNEg1NS4zdjIxLjZINDIuOFYzMS43aDI1LjhjNiwwLDEwLjcsMS42LDE0LjIsN
C43CgkJCQkJYzMuNSwzLjEsNS4zLDcuOSw1LjMsMTQuNEM4OC4yLDU3LjksODYuNCw2Mi45LDgyLjksNjUuOXogTTczLjMsNDQuMmMtMS42
LTEuMy0zLjgtMi02LjctMkg1NS4zdjE3LjdoMTEuMwoJCQkJCWMyLjksMCw1LjEtMC43LDYuNy0yLjJjMS42LTEuNCwyLjQtMy43LDIuNC0
2LjlDNzUuNyw0Ny43LDc0LjksNDUuNSw3My4zLDQ0LjJ6Ii8+CgkJCTwvZz4KCQk8L2c+Cgk8L2c+Cgk8Zz4KCQk8bGluZSBjbGFzcz0ic3
QyIiB4MT0iMTYuMyIgeTE9IjIzLjIiIHgyPSI4My40IiB5Mj0iODMuMiIvPgoJCTxnPgoJCQk8cG9seWdvbiBjbGFzcz0ic3QxIiBwb2lud
HM9IjEwMCw3NS43IDc0LjksOTQuMyA2NS45LDkxLjggOTIuMSw3Mi45IAkJCSIvPgoJCQk8Zz4KCQkJCTxwb2x5Z29uIHBvaW50cz0iNzQu
OSw5NC4zIDc0LjksOTkuMiA2NS45LDk2LjUgNjUuOSw5MS44IAkJCQkiLz4KCQkJCTxwb2x5Z29uIHBvaW50cz0iOTkuNyw4MS4zIDc0Ljk
sOTkuMiA3NC45LDk0LjMgMTAwLDc1LjcgCQkJCSIvPgoJCQk8L2c+CgkJPC9nPgoJPC9nPgo8L2c+Cjwvc3ZnPgo=
""")

RED_CAL_ICON = base64.decode("""
iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNS
R0IArs4c6QAAAGZJREFUOE9jZKAyYKSyeQwoBr6VUflPjgXCT+7AzYEzyDUM5gCYoWADKTUM2V
DaGPj//3+ywg49vBlBACQ4aiA5SRGsZzQMyQ46uEbahSE1Ejcsk6AUX+TmGJhh4KRDecihmkB1
AwEFRUAVgcjeRAAAAABJRU5ErkJggg==
""")

GREEN_CAL_ICON = base64.decode("""
iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAAXNSR0IArs4c6QAAAGRJREFUOE9j
ZKAyYKSyeQwoBipt9PlPjgX3/LfAzYEzyDUM5gCYoWADKTUM2VDaGPj//3+ywg49vBlBACQ4aiA5
SRGsZzQMyQ46uMbBHYawTAIvbSjJLTDDwEmH8pBDNYHqBgIAFrVAFR7m2MMAAAAASUVORK5CYII=
""")

def main(config):
    
    location = config.get("location", DEFAULT_LOCATION)
    loc = json.decode(location)
    timezone = loc.get("timezone", config.get("$tz", DEFAULT_TIMEZONE))
    now = time.now().in_location(timezone)

    results = get_data(now)
        
    if not results:
        return render.Root(child = render.Text("No data"))
 
    return render.Root(child = render.Column(
        expanded = True,
        main_align = "center",
        cross_align = "center",
        children = [
            render.Row(
                expanded = True,
                main_align = "center",
                cross_align = "center",
                children = [
                    render.Padding(
                        pad = (2, 0, 0, 0),
                        child = render.Image(
                            src = ASP_LOGO,
                            width = 16, 
                            height = 16
                        ),
                    ),
                    process_asp_results(results, now)
                ]
            )
        ]
    ))

def process_asp_results(results, now):
    day_abbr = {
        'Monday': 'M', 
        'Tuesday': 'T', 
        'Wednesday': 'W', 
        'Thursday': 'T', 
        'Friday': 'F', 
        'Saturday': 'S', 
        'Sunday': 'S'
    }
    children = []
    for index, item in enumerate(results):
        parsed_date = get_date_offset(now, index + 1)
        day_name = parsed_date.format("Monday")
        formatted_day = day_abbr.get(day_name, day_name)

        asp = item["asp"]
        asp_img = (
            render.Image(width = 11, height = 11, src=RED_CAL_ICON)
            if asp["CalendarDetailStatus"] 
            else render.Image(width = 11, height = 11, src=GREEN_CAL_ICON)
        )

        children.append(
            render.Padding(
                pad = (1, 0, 1, 0),
                child = render.Stack(
                    children = [
                        asp_img,
                        render.Padding(
                            pad = (4, 4, 0, 0),
                            child = render.Text(formatted_day, font="tom-thumb", color=BLACK)
                        )
                    ]
                )
            )
        )

    first_row = children[:3]
    second_row = children[3:6]
    
    return render.Column(
        main_align="center",
        cross_align="center",
        expanded=True,
        children=[
            render.Row(
                main_align="center",
                cross_align="center",
                expanded=True,
                children=first_row
            ),
            render.Row(
                main_align="center",
                cross_align="center",
                expanded=True,
                children=second_row
            )
        ]
    )


def get_data(now):
    results = []
    for i in range(6):
        day = get_query_date(now, offset=i + 1)
        url = NYC_PORTAL_URL + "/?today=" + day
        res = http.get(url)

        if res.status_code != 200:
            fail("request to %s failed with status code: %d - %s" % (url, res.status_code, res.body()))
        
        data = json.decode(res.body())
        results.append({
            "date": data["date"],
            "asp": data["results"][0]
        })
    
    return results

def get_date_offset(now, offset):
    hours_in_day = 24
    days = offset * hours_in_day
    duration = str(days) + "h"

    new_day = now + time.parse_duration(duration)

    return new_day

def get_query_date(now, offset):
    return get_date_offset(now, offset).format("1/02/2006")

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [],
    )