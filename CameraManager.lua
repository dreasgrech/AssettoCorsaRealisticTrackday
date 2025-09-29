local CameraManager = {}
-- carIndex is 0-based
CameraManager.followCarWithChaseCamera = function(carIndex)
  ac.focusCar(carIndex)                                 -- make that car the target
  ac.setCurrentCamera(ac.CameraMode.Drivable)           -- switch to “drivable” cameras
  ac.setCurrentDrivableCamera(ac.DrivableCamera.Chase)  -- pick the chase view (or .Chase2)
end

---Returns the index of the currently focused car
---@return integer
CameraManager.getFocusedCarIndex = function()
  local sim = ac.getSim()
  return sim.focusedCar
end

return CameraManager