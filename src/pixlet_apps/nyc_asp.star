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
GREEN = "#00FF00"
BLACK = "#000000"
RED = "#FF0000"
ASP_LOGO = '''
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
'''

def main(config):
    asp = get_data(config)
    date = get_print_date(config)
        
    if not asp:
        return render.Root(child = render.Text("No data"))

    asp_text = asp["CalendarDetailStatus"] if asp["CalendarDetailStatus"] else "In Effect"
    color = RED if asp["CalendarDetailStatus"] else GREEN
 
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
                            src = base64.decode(ASP_LOGO),
                            width = 16, 
                            height = 16
                        ),
                    ),
                    render.Padding(
                        pad = (2, 0, 0, 0),
                        child = render.Column(
                            expanded = True,
                            main_align = "center",
                            cross_align = "start",
                            children = [
                                render.Text(date),
                                render.Text(asp_text, color=color)
                            ]
                        )

                    )
                ]
            )
        ]
    ))

def get_data(config):
    day = get_query_date(config)
    res = http.get(NYC_PORTAL_URL + "/?today=" + day)
    if res.status_code != 200:
        print("Error fetching asp data")
        return []
    
    data = json.decode(res.body())
    asp = data["results"][0]
    return asp

def strip_after_period(s):
    result = ""
    for i in range(len(s)):
        c = s[i]
        if c == '.':
            break
        result += c
    return result

def get_next_day(config):
   location = config.get("location", DEFAULT_LOCATION)
   loc = json.decode(location)
   timezone = loc.get("timezone", config.get("$tz", DEFAULT_TIMEZONE))
   
   now = time.now().in_location(timezone)
   tom = now + time.parse_duration("24h")

   return tom

def get_query_date(config):
    return get_next_day(config).format("1/02/2006")

def get_print_date(config):
    return get_next_day(config).format("Jan 2")

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [],
    )