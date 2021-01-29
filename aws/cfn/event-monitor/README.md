# OVERVIEW
  - to add events POST a curl with the json you want to add
  - to retrieve events senda bunch of key=valeus and they will be matched to
  the json payload in the records. Do note this is a scan and it's slow (see
  TODO). Also search seems broken on nested items, which defeats the point of
  an "events" json key.

  Most likely the GET/read part will be rewritten as a dump to s3 rather than
  trying to have a more powerful search function here

# TODO

## Lambda Function
  - add logging / figure out how to print and fetch logs
  - implement search operators and conditions
  - implement limit and paging for result sets
  - for above two things probably need to move the search to a POST to specify
  more complex attributes and the add event to a PUT

## Dynamo
  - as is the table structure is useless for searches, forcing a scan. review
  it maybe forcing the client to send an event type which is probably
  something we'd want to key off of.
