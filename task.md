# Tasks

## Task 1
- Auto Pass Through url is not saved and is being reset after every app close. Fix this issue. 

## Task 2
### Brief
I want to create different profiles of endpoints. Such as if I am running the mock server for app1
I would probably want this profile to activate app1 profile and all its endpoints. Also since app1
and app2 may have endpoints with the same name with different response type. If I change the profile
the saved pass through url should change as well.

- In the manage endpoint section there should be a change profile icon on the app bar, which will show a bottom sheet to select profile
- On Top there would be turn on/off all endpoint button
- This would be backward compatible. Previous version of this app will be moved to a profile named default as fallback
- I would be able to turn on multiple profile at different port. If single profile is running the first page UI will be as is
- If there is more than one profile, there will be a bottom sheet asking to select profile. On select, the profile list will expand a little so that user can give the port number. A random port number is assigned by default.
- If more than one profile is running, the front page will show profile name, url copy icon, and stop sign in a list view. The listview will show 3 items at max by default. Clicking see all will expand with total items.
- View logs will have the same option. Log will be shown based on profile. There will be an option to change the profile which will prompt a bottom sheet to change the profile.


## Task 3
- The log is not realtime at this moment. I want this to be real time.
- I want to able to select multiple endpoint from the log so that I can create a profile with mock endpoints.
- In case of batch selection a default delay will be prompted.



---

## Pending

<!-- Add tasks here -->

## In Progress

<!-- Tasks currently being worked on -->

## Done

<!-- Completed tasks -->
