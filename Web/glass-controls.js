(() => {
  const preferenceKey = 'liferecord.glass-effects';
  const preference = document.querySelector('#webGlassEffects');
  preference.checked = localStorage.getItem(preferenceKey) !== 'off';
  const applyPreference = () => {
    document.documentElement.dataset.glass = preference.checked ? 'on' : 'off';
  };
  applyPreference();
  preference.addEventListener('change', () => {
    applyPreference();
    localStorage.setItem(preferenceKey, document.documentElement.dataset.glass);
  });

  let pressed;
  function release(event) {
    if (!pressed || (event?.pointerId != null && event.pointerId !== pressed.pointerId)) return;
    pressed.control.removeAttribute('data-pressed');
    pressed = undefined;
  }

  document.addEventListener('pointerdown', event => {
    if (!event.isPrimary || event.button !== 0) return;
    const control = event.target.closest('button, .glass-switch, .glass-segment, .glass-slider');
    if (!control || control.matches(':disabled') || control.querySelector('input:disabled')) return;
    release();
    pressed = { control, pointerId: event.pointerId };
    control.setAttribute('data-pressed', '');
  }, true);
  for (const event of ['pointerup', 'pointercancel', 'lostpointercapture']) {
    document.addEventListener(event, release, true);
  }
  document.addEventListener('pointermove', event => {
    if (pressed && event.pointerType === 'mouse' && !event.buttons) release(event);
  }, true);
  window.addEventListener('blur', release);
  window.addEventListener('pagehide', release);
})();
