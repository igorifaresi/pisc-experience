package pisc

import "core:fmt"
import ray "vendor:raylib"

SCREEN_WIDTH  :: 800
SCREEN_HEIGHT :: 450

draw_ui :: proc() {
	v1 : ray.Vector2
	v2 : ray.Vector2

	ray.DrawLineEx(v1, v2, 2.0, ray.WHITE)
}

toggle_fullscreen :: proc() {
	display := ray.GetCurrentMonitor()
 
	if (ray.IsWindowFullscreen()) {
	    ray.SetWindowSize(SCREEN_WIDTH, SCREEN_HEIGHT);
	} else {
	    ray.SetWindowSize(ray.GetMonitorWidth(display), ray.GetMonitorHeight(display))
	}

	ray.ToggleFullscreen()
}

main :: proc() {	
    ray.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "raylib [core] example - fullscreen toggle");

    ray.SetTargetFPS(60);

    toggle_fullscreen();

    for !ray.WindowShouldClose() {
 		/*if ray.IsKeyPressed(.ENTER) && ray.IsKeyDown(.LEFT_ALT) || ray.IsKeyDown(.RIGHT_ALT) {
 			
 		}*/

        ray.BeginDrawing();

        ray.ClearBackground(ray.BLACK);

        ray.DrawText("Press Alt + Enter to Toggle full screen!", 190, 200, 20, ray.LIGHTGRAY);

        ray.EndDrawing();
    }

    ray.CloseWindow()
}
