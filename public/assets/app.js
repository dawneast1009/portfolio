'use strict';
(() => {
  const menu = document.querySelector('.menu-toggle');
  const sidebar = document.getElementById('sidebar');
  const backdrop = document.querySelector('.menu-backdrop');
  const closeMenu = () => {
    document.body.classList.remove('menu-open');
    menu?.setAttribute('aria-expanded', 'false');
    if (backdrop) backdrop.hidden = true;
  };
  menu?.addEventListener('click', () => {
    const open = !document.body.classList.contains('menu-open');
    document.body.classList.toggle('menu-open', open);
    menu.setAttribute('aria-expanded', String(open));
    backdrop.hidden = !open;
    if (open) sidebar?.querySelector('a')?.focus();
  });
  backdrop?.addEventListener('click', closeMenu);
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && document.body.classList.contains('menu-open')) { closeMenu(); menu?.focus(); }
    if (event.key === 'Tab' && document.body.classList.contains('menu-open')) {
      const items = [...sidebar.querySelectorAll('a,button,input')].filter(item => item.offsetParent !== null);
      if (event.shiftKey && document.activeElement === items[0]) { event.preventDefault(); items.at(-1)?.focus(); }
      if (!event.shiftKey && document.activeElement === items.at(-1)) { event.preventDefault(); items[0]?.focus(); }
    }
  });
  matchMedia('(min-width: 768px)').addEventListener('change', event => { if (event.matches) closeMenu(); });
  let timer;
  function toast(message) {
    const node = document.querySelector('.toast');
    if (!node) return;
    clearTimeout(timer); node.textContent = message; node.hidden = false;
    timer = setTimeout(() => { node.hidden = true; }, 4500);
  }
  async function copyAddress(address) {
    const url = new URL(address, location.href);
    if (!['http:', 'https:'].includes(url.protocol) || ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) {
      toast('이 주소는 내 컴퓨터에서만 열립니다. 배포 후 실제 사이트 주소를 제출하세요.');
      return;
    }
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(url.href);
      toast('링크를 복사했습니다');
    } catch {
      const dialog = document.getElementById('copy-dialog');
      const field = document.getElementById('copy-value');
      field.value = url.href;
      dialog.showModal(); field.focus(); field.select();
    }
  }
  document.querySelector('[data-copy-page]')?.addEventListener('click', () => {
    const url = new URL(location.href); url.search = ''; url.hash = '';
    if (url.pathname.startsWith('/admin')) url.pathname = '/';
    copyAddress(url.href);
  });
  document.querySelector('[data-copy-home]')?.addEventListener('click', () => copyAddress(document.getElementById('share-url').value));
  document.querySelectorAll('form[data-confirm]').forEach(form => form.addEventListener('submit', event => {
    if (!confirm(form.dataset.confirm)) event.preventDefault();
  }));
  document.querySelectorAll('[data-dropzone]').forEach(zone => {
    const input = zone.querySelector('[data-file-input]');
    const label = zone.querySelector('[data-file-label]');
    if (!input) return;
    const showName = () => { if (label && input.files[0]) label.textContent = input.files[0].name; };
    input.addEventListener('change', showName);
    ['dragenter', 'dragover'].forEach(type => zone.addEventListener(type, event => { event.preventDefault(); zone.classList.add('dragover'); }));
    ['dragleave', 'drop'].forEach(type => zone.addEventListener(type, event => { event.preventDefault(); zone.classList.remove('dragover'); }));
    zone.addEventListener('drop', event => {
      if (event.dataTransfer.files.length !== 1) { toast('파일은 한 번에 하나씩 첨부하세요'); return; }
      try { input.files = event.dataTransfer.files; showName(); }
      catch { toast('파일 선택 버튼을 사용해 주세요'); }
    });
  });
  let dirty = false;
  document.querySelector('[data-unsaved-form]')?.addEventListener('input', () => {
    dirty = true; const status = document.querySelector('[data-save-status]');
    if (status) status.textContent = '저장되지 않은 변경 내용이 있습니다';
  });
  document.querySelector('[data-unsaved-form]')?.addEventListener('submit', () => { dirty = false; });
  document.querySelector('.upload-form')?.addEventListener('submit', event => {
    if (dirty && !confirm('본문에 저장하지 않은 내용이 있습니다. 파일을 첨부하면 해당 변경 내용은 사라집니다. 계속할까요?')) event.preventDefault();
    else if (!event.defaultPrevented) dirty = false;
  });
  window.addEventListener('beforeunload', event => { if (dirty) { event.preventDefault(); event.returnValue = ''; } });
})();
