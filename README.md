# Assetto Corsa Realistic Trackday
<img width="128" height="128" align="right" alt="AssettoCorsaRealisticTrackday_Icon" src="https://github.com/user-attachments/assets/ad8cd56e-59d9-4f5e-9205-4c51013f69c4" />

**Assetto Corsa Realistic Trackday** is an app for <a href="https://store.steampowered.com/app/244210/Assetto_Corsa/" target="_blank">Assetto Corsa</a> which alters the AI cars' behaviour to act like humans driving on a track day aware of other cars as opposed to bots with horse blinkers constantly driving the racing line.


Using this app, AI cars will yield to faster cars by driving to the side and only yielding to one pre-defined side (left or right) as is the way during trackdays, particularly on the Nordschleife.  AI cars will also overtake other cars on the other side and return back to the racing line once it's safe to do so.

This provides the user a smooth single-player driving experience with AI cars where the vehicles respect each other while driving and act like real drivers do.
<br><br>
> [!NOTE]
> If you enjoy the app, it would be immensely appreciated if you could give it a rating at the Overtake.gg page: https://www.overtake.gg/downloads/assetto-corsa-realistic-trackday.80212/
<p align="center">
    <a href="https://www.overtake.gg/downloads/assetto-corsa-realistic-trackday.80212/"><img width="500" alt="image" src="https://github.com/user-attachments/assets/de1613b2-3801-41e8-afdc-48cf7bb2176c" /></a>
</p>

<br><br>
My main aim with this is to recreate the true <a href="https://youtu.be/nQ9j9Wlm410?si=A4LDo-DjJOClf2i4&t=312" target="_blank">Nordschleife Touristenfahrten</a> experience where by law you are required to overtake only on the left and thus yielding cars always need yield to the right.
<br/><br/>
<img width="931" height="238" alt="image" src="https://github.com/user-attachments/assets/6080f0a1-425d-4202-a7d8-81662d4f33c2" />

*Source: https://nuerburgring.de/info/company/gtc/driving-regulations*

## Videos

Assetto Corsa Realistic Trackday v0.9.8 - Full Feldbergring lap: [https://www.youtube.com/watch?v=s0Gfu2ucrX8](https://www.youtube.com/watch?v=FYDH1OwxDWw)

https://github.com/user-attachments/assets/968fa828-86cc-4aba-b6db-5c0471d45557

Full Nordschleife lap on Realistic Trackday v0.9: https://www.youtube.com/watch?v=s0Gfu2ucrX8
<br><br><br>
<p align="center">
  <img src="https://github.com/user-attachments/assets/7e70ad67-8aa5-435e-8da1-5f6fb3c87325"/>
</p>

Short video of Realistic Trackday v0.5: https://www.youtube.com/watch?v=v83cmlmwVZs
<br/><br/>
## v0.9.8 - Major Update - Improvements across the board!

Realistic Trackday v0.9.8 brings a lot of new features over the previous v0.9.1 version, notably the number of tweakable options now available to the user.

### Per-Track-Per-Mode Settings

One of the first important changes is that the app now saves settings Per-Track-Per-Mode where Mode can be any one of the following values depending on how the game is launched from the Content Manager:
- Practice
- Qualify
- Race
- Hotlap
- TimeAttack
- Drift
- Drag

<p align="center">
<img width="495" height="117" alt="image" src="https://github.com/user-attachments/assets/43a000b4-433d-4fcc-88c9-9e550f57ddbe" />
</p>

This means that you will have separate settings for, for example, running a trackday on the Nordschleife versus launching a race on the same track.

### App now starts disabled until enabled for the current Track-Mode combination

Another important change is that now, unless previously enabled for the current Track-Mode combination, the Realistic Trackday app starts disabled and you have to enable it from the Realistic Trackday Settings.  This change was done so that the app doesn't modify the AI cars' behaviour unexpectedly.

<p align="center">
<img width="1024" height="235" alt="image" src="https://github.com/user-attachments/assets/b86faa8b-326b-4eaa-8b9f-d29e9ef27c32" />
</p>

### Separate customizable values for default, yielding and overtaking lanes

The third important change involves the way the yielding and overtaking "lanes" are defined.  In v0.9.1, you could define the yielding lane as either Left or Right and the overtaking lane will then be the other side of the track and how far the ai cars drive to the side of the track for both yielding and overtaking was defined by a single value.  In v0.9.8, there are three slider values which define the default driving position, the yielding position and the overtaking position:

- Default Lateral Offset
- Yielding Lateral Offset
- Overtaking Lateral Offset

<p align="center">
<img width="950" height="159" alt="image" src="https://github.com/user-attachments/assets/8e00ec10-a244-42f2-a112-2b06a9b53d47" />
</p>


These three numbers are all in the range of [-1..1] where -1 represents the left-most side (edge) of the track, 0 is the middle of the track and 1 the right-most side of the track (edge).

All three specify the lateral position on the track width where each respective action should take place.

<p align="center">
  <img width="566" height="456" alt="image" src="https://github.com/user-attachments/assets/334724a4-fc72-425d-94c4-0807c4da8bf8" />
</p>

Here are some examples of how they can be used:

**Nordschleife Touristenfahrten Trackday where driving normally is mostly done on the racing lane, overtaking happens on the left and yielding takes place on the right**:<br/>
`Default Lateral Offset: 0` (when the lateral offset is 0, the ai use the default racing line which is mostly at the center of the track)<br/>
`Yielding Lateral Offset: 0.7` (we want the cars to yield to the right so an 0.7 will make them yield to the right but not going as far the edge of the track)<br/>
`Overtaking Lateral Offset: -0.8` (we want the cars to overtake on the left so a -0.8 will make them overtake to the left but also not going as far the edge of the track)<br/>

<p align="center">
<img width="948" height="145" alt="image" src="https://github.com/user-attachments/assets/2ab4aafe-baa5-45f1-b10d-3ac9275e5a28" />
</p>
<br/><br/>

**A Germany unidirectional two lane road where driving normally is done on the right lane and overtaking is done on the left lane:**<br/>
`Default Lateral Offset: 0.5` (an 0.5 will make the cars drive in the middle of the right lane)<br/>
`Yielding Lateral Offset: 0.5` (since this is a road and not a track and the cars are already driving on the right lane by default, we can use the same value here we used for the Default Lateral Offset)<br/>
`Overtaking Lateral Offset: -0.5` (to make the cars overtake by moving to the middle of the left lane, we can use a -0.5 value)<br/>

<p align="center">
<img width="946" height="151" alt="image" src="https://github.com/user-attachments/assets/40dfbf6a-0e34-438e-a383-16e30ec9e7ac" />
</p>
<br/><br/>

**A UK unidirectional two lane road where driving normally is done on the left lane and overtaking is done on the right lane:**<br/>
`Default Lateral Offset: -0.5` (a -0.5 value will make the cars drive in the middle of the left lane)<br/>
`Yielding Lateral Offset: -0.5` (since this is a road and not a track and the cars are already driving on the left lane by default, we can use the same value here we used for the Default Lateral Offset)<br/>
`Overtaking Lateral Offset: 0.5` (to make the cars overtake by moving to the middle of the right lane, we can use a 0.5 value)<br/>

<p align="center">
<img width="940" height="150" alt="image" src="https://github.com/user-attachments/assets/a5fce98c-8d46-4acd-a4c1-726eeccc8877" />
</p>
<br/><br/>

By exposing these three individual values, the app can also be used for simulating road traffic on a street instead of just yielding/overtaking on the track.

### Many customizable options

The fourth important change is the amount of available tweakable values now available to the user.  These tweakable values include dynamic changes to AI Caution, AI Aggression and AI Difficulty level.

<img width="1639" height="292" alt="image" src="https://github.com/user-attachments/assets/3e77dfba-c58b-4f57-943a-73eb925e962a" />

There are also many individual settings for how to handle yielding and overtaking:

<p align="center">
<img width="1046" height="436" alt="image" src="https://github.com/user-attachments/assets/5a213039-6a5f-4dae-bd7f-05ead63044cc" />
</p>


Hopefully all these tweakable values will better provide the user create the perfect trackday experience.

### Better support for races

Although Realistic Trackday wasn't specifically for races, there are a number of values you can tweak about to make it work in a race.  Follow these tips to get a better racing experience:
- Very important: Set a value in seconds in the "Defer yielding/overtaking for a while after session start" so that the yielding and overtaking logic doesn't start taking place until after some time so that the cars don't pile up when the race starts.
- Keep Caution values low so that the AI cars take more risks overall, but careful about dropping the Caution values below 1.
- Keep Aggression values high so that the AI cars drive more assertively on track.
- Keep Difficulty values high so that they go through corners faster.
- Keep the "Detect car behind distance" Yielding value low so that AI cars only yield if the overtaking car is very close to them
- Keep the "Detect car behind ahead" Overtaking value low so that AI cars only overtake if the yielding car is very close to them
- Set the top speed limit Yielding value to 1.0 so that no top speed limit is applied when a car is yielding
- Keep the throttle pedal limit Yielding value high so that yielding cars don't let go of the throttle too much while yielding, or nothing at all.
- Keep the "distance to overtaking car to apply speed limit" Yielding value low so that the yielding car only slows down, if you want it to slow down, while very close to the overtaking car.

### Checking for required Custom Shaders Patch functionality

In this version I've written better handling for users with outdated CSP versions by trying to identify all the required functions in the app and informing you if any of them are missing due to old CSP versions.

<p align="center">
<img width="832" height="338" alt="image" src="https://github.com/user-attachments/assets/142da955-5800-4822-a03d-059d8a498de6" />
</p>




## Installation
The app requires <a href="https://acstuff.club/patch/" target="_blank">Custom Shaders Patch</a> (CSP) extension installed and doesn't work online since it can, *obviously*, only control AI cars.

> [!NOTE]
> The recommended Custom Shaders Patch version as of 07/11/25 is <a href="https://www.patreon.com/posts/quick-fix-for-142367147" target="_blank">CSP v0.3.0-preview140</a>.


### Stable
Download the zip file from the Releases page: https://github.com/dreasgrech/AssettoCorsaRealisticTrackday/releases

> [!WARNING]
> When upgrading from an existing version of Realistic trackday, make sure to first delete the `RealisticTrackday` app directory before copying the new one.

Copy the `AssettoCorsaRealisticTrackday` directory to `\steamapps\common\assettocorsa\apps\lua\`

### Cutting Edge
If you want to install the app directly using the latest source code, you can download the entire repository and put all files in: `\steamapps\common\assettocorsa\apps\lua\AssettoCorsaRealisticTrackday\`

> [!WARNING]
> *There's no guarantee everything will work as expected when using the cutting edge "nightly" code here since I am constantly committing in untested code when I'm working on the app.*

<br><br><br>
You should end up with this file structure once the files are copied:

<img width="768" height="789" alt="image" src="https://github.com/user-attachments/assets/1a4a5f7b-5445-458b-a599-de0d2eadcd6b" />

## How To Use
Once installed, the app will run automatically when Assetto Corsa is running.

To view the car list table in the window, open the app from the side bar in the game listed as `Realistic Trackday`:

<img width="241" height="27" alt="image" src="https://github.com/user-attachments/assets/a315ab48-cd4d-434e-920a-4bf0c304aba1" />

*More information about the car list table below.*

I have tested this app mostly using the `AI Flood` setting which cycles the AI cars during a Trackday around the player so that there's a constant stream of cars behind and in front of the player car.

It can be enabled from `Content Manager -> Settings -> Custom Shaders Patch -> New AI Behaviour`:

<img width="2533" height="131" alt="image" src="https://github.com/user-attachments/assets/7498a1e9-883c-44a4-90b0-679ab7bea411" />

That said, the app should theoratically work in all modes (except Online) on tracks that have an AI Spline set.

Here's a typical scenario which can be used:

<img width="1353" height="794" alt="image" src="https://github.com/user-attachments/assets/4826abbb-b497-4463-b822-b18a43d2e7e4" />


## Settings
The app offers a number of settings to allow for customizing the experience as much as possible, starting from the general driving of the AI to specific settings regarding yielding and overtaking:

<img width="1672" height="1369" alt="image" src="https://github.com/user-attachments/assets/50ac2c33-77b9-4724-bdae-4a9538091a11" />


There are also a number of settings that help with understanding what the app is doing under the hood.  One of the main debugging tools is the custom UI table that shows the full relevent data about the cars:

<img width="2560" height="333" alt="image" src="https://github.com/user-attachments/assets/153256c0-9eba-4d31-935b-419e053c7d9a" />

This table shows you a lot of information about each other including the current state the car is in, if it's yielding or overtaking and who's the other car involved, and also reasons why they can't yield or overtake at the time beind.  It's invaluable for understanding the behaviour of the cars.

> [!CAUTION]
> Keep the car list table and all other Debugging options disabled during regular usage of the app so that you don't incur the performance hit they entail.

## How It Works
### Car States
Each AI car is represented as a state machine where each car can be in one state at a time.

These are all the current states AI cars can be in:

#### Default Driving States

##### Driving Normally
The default state where cars are driving the normal racing line while not currently yielding or overtaking other cars.  In this state, a car is constantly monitoring the cars around it to determine whether it needs to overtake the car in front or yield to the car in the rear.
If a car needs to start yielding to a car behind, it will transition to the **Easing In Yield** state or the **Easing In Overtake** if it needs to overtake a car in front of it.

<p align="center">
  <img width="566" height="456" alt="image" src="https://github.com/user-attachments/assets/46072143-593e-415b-abfb-ac46bb9ac7db" />
</p>
<br>

#### Yielding States

##### Easing In Yield
In this state cars are driving laterally from their current lateral position on the track to the yielding lane to let faster cars behind them overtake on the overtaking lane.  To ease into the yielding lane, cars drive slowly to the side while checking to make sure there are no other cars on the side they are driving lateral to.  If they encounter cars on their side while easing in yielding, they will slow down and wait for a gap to fit in on the yielding lane to let the overtaking car pass.  
When a car has fully reached the yielding lane, they will move on to the **Staying on Yielding Lane** state.

<p align="center">
  <img width="566" height="456" alt="image" src="https://github.com/user-attachments/assets/3a1df57f-d1a3-4c51-bb1e-c512834e5ba6" />
</p>


##### Staying on Yielding Lane
When a car is in the **Staying on Yielding Lane** state, a car will keep driving on the yielding lane side as much as possible to let the overtaking cars pass .  While in this state, cars will try drive a bit safer by keeping a two car gap on the yielding lane.
When a car determines that there's no one else behind it that needs yielding, it will transition to the **Easing Out Yield** state.

<p align="center">
  <img width="566" height="456" alt="image" src="https://github.com/user-attachments/assets/d3411593-52d2-4297-b4f9-0bcaed8f6cb7" />
</p>

##### Easing Out Yield
When back to the **Easing Out Yield** state, a car will drive laterally from the yielding lane over to the normal racing line and will transition back to the **Driving Normally** state once it reaches the racing line spline.  If it encounters a car on its side while driving laterally, it will stop driving to the side and wait until the car on the side has created a gap before it returns to the racing line.

<p align="center">
  <img width="566" height="456" alt="image" src="https://github.com/user-attachments/assets/23a55a35-eaba-4949-b882-e292ec3f894f" />
</p>

<br><br>
#### Overtaking States

##### Easing In Overtake
While in the **Easing In Overtake**, a car will drive laterally from their current lateral position on the track to the overtaking lane so that they can overtake the car or cars in front of them.

<p align="center">
  <img width="566" height="456" alt="image" src="https://github.com/user-attachments/assets/5bf42378-e19a-4419-972a-6e62e9f43cdd" />
</p>

##### Staying On Overtaking lane
After a car overtakes another car, it will check if it should stay on the overtaking lane to continue overtaking the upcoming car before returning back to the normal driving line through the **Easing Out Overtake** state.  
Once an overtaking car has determined it's far enough from the yielding car and there's no more close cars that can be overtaken, it will start returning back to the normal racing line via the **Easing Out Overtake** state.

<p align="center">
  <img width="566" height="456" alt="image" src="https://github.com/user-attachments/assets/baf90110-a9cf-4e51-a0af-fbc13bd1c9db" />
</p>

##### Easing Out Overtake
When back on the **Easing Out Overtake** state, a car will drive laterally from the overtaking over to the normal racing line and will transition back to the **Driving Normally** state once it reaches the racing line spline.  If it encounters a car on its side while driving laterally, it will stop driving to the side and wait until the car on the side has created a gap before it returns to the racing line.

<p align="center">
  <img width="566" height="456" alt="image" src="https://github.com/user-attachments/assets/5ca3100b-6995-4fb4-a249-f86f845dfdb6" />
</p>

<br><br>
#### Accident States (WORK IN PROGRESS)

##### Collided with Car (WIP)
##### Collided with Track (WIP)
##### Another Car Collided Into Me (WIP)

## Troubleshooting
- If you don't see the car list table and want to enable it, you can enable it from the Settings called `Draw Car List`.
- If the AI cars are frequently going off track while yielding/overtaking, reduce the `Max Side Offset` value from the Settings:
  
  <img width="645" height="82" alt="image" src="https://github.com/user-attachments/assets/d9bb3a39-b36a-4aa9-b7fc-08ae8bc18608" />

- If nothing seems to be working, open the Lua Debug app:
  
  <img width="250" height="186" alt="image" src="https://github.com/user-attachments/assets/374bace7-6d85-41a3-9295-c8cf296caf2b" />

  Enable the `Realistic Trackday` app:

  <img width="921" height="95" alt="image" src="https://github.com/user-attachments/assets/3552f0e3-f622-437f-ab61-720a55ba5023" />

  And check if there are any errors listed in the window (*the yellow logs in the below image are from the `Log fast AI state changes` option*):

  <img width="1529" height="330" alt="image" src="https://github.com/user-attachments/assets/b9c28077-3c33-4143-8849-c07e590b5050" />

- If when using the app in a Race, the cars all start trying to yield and overtake as soon as the race starts causing mayhem, increase the "Defer yielding/overtaking for a while after session start" value which determines the delay before the yielding/overtaking starts working after a session officially starts.
- If the cars start yielding while the overtaking car is still very far, decrease the "Detect car behind distance" value in the Yielding settings.
- If the cars start overtaking while the yielding car is still very far, decrease the "Detect car behind ahead" value in the Overtaking settings.
- If the cars are rear-ending each other frequently, increase the Caution values.  Note that a caution value below 1 causes the cars to drive very assertively irrespective of what's in front of them.
- If the cars are very hesitant when trying to overtake, decrease the overtaking Caution values, increase Aggression values and increase Difficulty values.  Also make sure that the overtaking lateral offset is far enough from the yielding lateral offset so that cars have enough space on the side to overtake.
- If the yielding cars are driving way too fast while yielding causing the overtaking cars to not be able to fully overtake them, adjust the speed limiting values in the Yielding section to tell the yielding cars to slow down a bit while yielding so that the overtaking car can overtake safely.
- If the cars are changing directions while yielding/overtaking too fast with jerky steering pulls, decrease the lateral offset increment/decrement step values in the Yielding and Overtaking sections so that the move to the target lateral offset happens more gradually.
- If the cars are hitting each other side-to-side when driving laterally to change lanes, make sure that the "Check sides while yielding" and "Check sides while overtaking" in the Yielding and Overtaking sections respectively are enabled.

## Known Issues
- Some cars don't use the indicator lights when yielding or overtaking (like the Alfa Mito), and some cars (like the MX5) seem to have invertly-set indicator lights i.e. they turn on the left indicator light when going right and vice versa.  This seems to be an issue either with the CSP API or with the specific individual cars.
- As of CSP `v0.2.12-preview1`, there seems to be a bug with the API in regards to speed-limit functions on the API cars (specifically the `physics.setAIThrottleLimit` and `physics.setAITopSpeed` functions) which prevents the AI cars slowing down while yielding to another car.
- Accident handling hasn't yet been enabled in the app, even though it's almost fully developed.  This involves having the cars stop after accidents, a yellow flag being shown to the player indicating there's an accident, no overtaking of cars in yellow flag zone, everyone driving at 50km/h and also ai cars navigating around the cars in the accident on the track.  But I haven't enabled it yet because of the issue in the current CSP `v0.2.12-preview1` which doesn't have the ai speed limiting code working (see point above for more info) and I need the speed limiting to work for the cars to navigate accidents.
- Since accidents aren't implemented yet, cars will now sometimes drive back to the track after they crash so beware of that.
- More TODOs and issues listed on the Issues page: https://github.com/dreasgrech/AssettoCorsaRealisticTrackday/issues

## Thank You
This app has taken many many hours of development work to get it in the state it is today, so if you enjoy using it, please consider buying me a coffee.  It will be immensely appreciated.

<a href="https://buymeacoffee.com/dreasgrech" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/purple_img.png" alt="Buy Me A Coffee" style="height: 41px !important;width: 174px !important;box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;-webkit-box-shadow: 0px 3px 2px 0px rgba(190, 190, 190, 0.5) !important;" ></a>

![541071877_18289519078282595_5138839538470946793_n_](https://github.com/user-attachments/assets/97cc68b6-5942-465e-b3c1-4c170b929692) ![racetracker_39753918_619967__](https://github.com/user-attachments/assets/32a6c8c3-dccb-47a0-bb18-98d946f5b80f)
