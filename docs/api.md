# API (V1)

The base path to all requests is: `/api/v1`

The version guarantees backwards compatibility: No attribute will change meaning or value.
However any attributes may be added or additional values become valid.

All requests must include a valid `key` parameter as part of the query in the url.

## Servers

### GET `/servers/`

Returns a list of servers and their state.

Example:

```json
{
  "length": 2,
  "servers": [
    {
      "address": "",
      "bookable": false,
      "connect-string": "connect ; password \"\"; rcon_password \"\"",
      "name": "ozfortress-1",
      "status": "Stopped"
    },
    {
      "address": "40.126.229.205:27016",
      "bookable": true,
      "connect-string": "connect 40.126.229.205:27016; password \"X/psb0UOFEjog7uar7F2SCEvFqK8/1lvNvXnOKOcYTc=\"; rcon_password \"X/psb0UOFEjog7uar7F2SCEvFqK8/1lvNvXnOKOcYTc=\"",
      "name": "ozfortress-2",
      "status": "Active"
    }
  ]
}
```

### POST `/servers/restart/`

Marks all servers as dirty, restarting any that are running but not booked.

Returns nothing.

## Bookings

### POST `/bookings/`

Creates a new booking.

Returns booking information.

Query Parameters:
- `user`: The user to book a server under.
- `hours`: The number of hours to book a server for.

Example:

```json
{
  "user": "foo",
  "client": "client-name",
  "server": {
    "address": "40.126.229.205:27016",
    "bookable": true,
    "connect-string": "connect 40.126.229.205:27016; password \"X/psb0UOFEjog7uar7F2SCEvFqK8/1lvNvXnOKOcYTc=\"; rcon_password \"X/psb0UOFEjog7uar7F2SCEvFqK8/1lvNvXnOKOcYTc=\"",
    "name": "ozfortress-2",
    "status": "Active"
  },
  "startedAt": "2017-02-06T12:11:52",
  "endsAt": "2017-02-06T14:11:52"
}
```

### GET `/bookings/:user`

Gets a booking by the user the booking was made under.

Returns booking information.

Example:

```json
{
  "user": "foo",
  "client": "client-name",
  "server": {
    "address": "40.126.229.205:27016",
    "bookable": true,
    "connect-string": "connect 40.126.229.205:27016; password \"X/psb0UOFEjog7uar7F2SCEvFqK8/1lvNvXnOKOcYTc=\"; rcon_password \"X/psb0UOFEjog7uar7F2SCEvFqK8/1lvNvXnOKOcYTc=\"",
    "name": "ozfortress-2",
    "status": "Active"
  },
  "startedAt": "2017-02-06T12:11:52",
  "endsAt": "2017-02-06T14:11:52"
}
```

### DELETE `/bookings/:user`

Ends a booking made under a user.

Returns nothing.
