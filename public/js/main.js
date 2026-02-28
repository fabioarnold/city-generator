const canvas = document.querySelector("canvas");
resizeCanvas();

window.addEventListener("resize", resizeCanvas);
function resizeCanvas() {
    canvas.width = devicePixelRatio * window.innerWidth;
    canvas.height = devicePixelRatio * window.innerHeight;
}

const read_char_string = (ptr, len) => {
    const array = new Uint8Array(memory.buffer, ptr, len);
    const decoder = new TextDecoder();
    return decoder.decode(array);
};
const read_char_string_zero = (ptr) => {
    const array = new Uint8Array(memory.buffer, ptr);
    const length = array.indexOf(0);
    const decoder = new TextDecoder();
    return decoder.decode(array.subarray(0, length));
};

const wasm_performance_now = () => performance.now();

let log_string = "";
const wasm_log_write = (ptr, len) => {
    log_string += read_char_string(ptr, len);
};
const wasm_log_flush = () => {
    console.log(log_string);
    log_string = "";
};
const wasm_set_cursor = (ptr, len) => {
    document.body.style.cursor = read_char_string(ptr, len);
}
const wasm_open_link = (ptr, len) => {
    const url = read_char_string(ptr, len);
    window.open(url, '_blank');
}
const key_state = [];
addEventListener("keydown", e => key_state[e.keyCode] = true);
addEventListener("keyup", e => key_state[e.keyCode] = false);
const wasm_key_down = (key) => {
    return key_state[key] === true;
}
const button_mapping_standard = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];
const button_mapping_raw = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];
const get_gamepad = (gamepad_index) => {
    const gamepads = (navigator.getGamepads ? navigator.getGamepads() : []).filter(gp => gp && gp.buttons.length > 1);
    return gamepad_index < gamepads.length ? gamepads[gamepad_index] : null;
}
const wasm_button_down = (gamepad_index, button_index) => {
    const gamepad = get_gamepad(gamepad_index);
    if (!gamepad) return false;
    const mapping = gamepad.mapping === "standard" ? button_mapping_standard : button_mapping_raw;
    button_index = mapping[button_index];
    return button_index < gamepad.buttons.length ? gamepad.buttons[button_index].pressed : false;
}
const deadzone = 0.1;
const wasm_stick_x = (gamepad_index, stick_index) => {
    const gamepad = get_gamepad(gamepad_index);
    const axis_index = 2 * stick_index;
    const axis = gamepad && axis_index < gamepad.axes.length ? gamepad.axes[axis_index] : 0;
    return (Math.abs(axis) < deadzone) ? 0 : axis;
}
const wasm_stick_y = (gamepad_index, stick_index) => {
    const gamepad = get_gamepad(gamepad_index);
    const axis_index = 2 * stick_index + 1;
    const axis = gamepad && axis_index < gamepad.axes.length ? gamepad.axes[axis_index] : 0;
    return (Math.abs(axis) < deadzone) ? 0 : axis;
}

async function main() {
    const params = new URLSearchParams(window.location.search);


    init_webgl();

    let saved_state = new Uint8Array(0);

    const wasm_save_state = (ptr, len) => {
        const array = new Uint8Array(memory.buffer, ptr, len);
        let binary = '';
        for (let i = 0; i < len; i++) {
            binary += String.fromCharCode(array[i]);
        }
        localStorage.setItem("city_map", btoa(binary));
    };

    const wasm_get_state_size = () => {
        const b64 = localStorage.getItem("city_map");
        if (!b64) return 0;
        const binary = atob(b64);
        saved_state = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
            saved_state[i] = binary.charCodeAt(i);
        }
        return saved_state.length;
    };

    const wasm_read_state = (ptr, len) => {
        const array = new Uint8Array(memory.buffer, ptr, len);
        array.set(saved_state);
    };

    const env = {
        wasm_performance_now,
        wasm_log_write,
        wasm_log_flush,
        wasm_set_cursor,
        wasm_open_link,
        wasm_key_down,
        wasm_button_down,
        wasm_stick_x,
        wasm_stick_y,
        wasm_save_state,
        wasm_get_state_size,
        wasm_read_state,
        ...webgl_env,
        // ...audio_env,
    };

    const response = await fetch("bin/main.wasm");
    const bytes = await response.arrayBuffer();
    const results = await WebAssembly.instantiate(bytes, { env });
    window.instance = results.instance;
    window.memory = instance.exports.memory;
    instance.exports.on_init();
    instance.exports.on_resize(innerWidth, innerHeight, devicePixelRatio);
    addEventListener("resize", () => instance.exports.on_resize(innerWidth, innerHeight, devicePixelRatio));
    addEventListener("mousemove", e => instance.exports.on_mouse_move(e.x, e.y, e.movementX, e.movementY));
    addEventListener("mousedown", e => instance.exports.on_mouse_down(e.button, e.x, e.y));
    addEventListener("mouseup", e => instance.exports.on_mouse_up(e.button, e.x, e.y));
    addEventListener("contextmenu", e => e.preventDefault());
    addEventListener("touchmove", e => instance.exports.on_mouse_move(e.touches[0].pageX, e.touches[0].pageY));
    addEventListener("touchstart", e => instance.exports.on_mouse_down(0, e.touches[0].pageX, e.touches[0].pageY));
    addEventListener("touchend", e => instance.exports.on_mouse_up(0, e.touches[0].pageX, e.touches[0].pageY));
    addEventListener("keydown", e => instance.exports.on_key_down(e.keyCode));
    addEventListener("beforeunload", () => instance.exports.on_save());

    // setInterval(() => {
    //     instance.exports.on_fixed_update(10);
    // }, 10);
    const draw = () => {
        instance.exports.on_animation_frame();
        requestAnimationFrame(draw);
    }
    draw();
}
main();

function open_file_picker() {
    return new Promise(resolve => {
        const input = document.createElement("input");
        input.type = "file";
        input.accept = ".json,application/json";
        input.style.display = "none";
        input.addEventListener("change", () => resolve(input.files));
        input.click();
    });
}
