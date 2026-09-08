'use strict';

// All essential operations use normal HTML forms. JavaScript adds small UX improvements.
document.documentElement.classList.add('js-ready');

const menuButton = document.querySelector('.nav-toggle');
const menu = document.querySelector('#site-nav');
if (menuButton && menu) {
  menuButton.addEventListener('click', () => {
    const open = menuButton.getAttribute('aria-expanded') !== 'true';
    menuButton.setAttribute('aria-expanded', String(open));
    menuButton.setAttribute('aria-label', open ? '메뉴 닫기' : '메뉴 열기');
    menu.classList.toggle('is-open', open);
  });
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && menu.classList.contains('is-open')) {
      menu.classList.remove('is-open');
      menuButton.setAttribute('aria-expanded', 'false');
      menuButton.setAttribute('aria-label', '메뉴 열기');
      menuButton.focus();
    }
  });
}

for (const form of document.querySelectorAll('form[data-confirm]')) {
  form.addEventListener('submit', (event) => {
    if (!window.confirm(form.dataset.confirm)) event.preventDefault();
  });
}

const uploadForm = document.querySelector('[data-upload-form]');
if (uploadForm) {
  const input = uploadForm.querySelector('input[type="file"]');
  const zone = uploadForm.querySelector('[data-drop-zone]');
  const selection = uploadForm.querySelector('[data-file-selection]');
  const submit = uploadForm.querySelector('[data-upload-submit]');
  const maxBytes = Number(uploadForm.dataset.maxBytes);
  const extensions = new Set(['pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt', 'md', 'zip']);

  const showSelection = () => {
    input.setCustomValidity('');
    zone.classList.remove('invalid');
    const file = input.files[0];
    if (!file) {
      selection.textContent = '선택한 파일이 없습니다';
      return;
    }
    const extension = file.name.includes('.') ? file.name.split('.').pop().toLowerCase() : '';
    let error = '';
    if (!extensions.has(extension)) error = '지원하지 않는 파일 형식입니다';
    else if (file.size === 0) error = '빈 파일은 업로드할 수 없습니다';
    else if (file.size > maxBytes) error = `최대 ${(maxBytes / 1048576).toFixed(0)} MiB까지 업로드할 수 있습니다`;
    if (error) {
      input.setCustomValidity(error);
      zone.classList.add('invalid');
      selection.textContent = error;
    } else {
      const size = file.size >= 1048576 ? `${(file.size / 1048576).toFixed(1)} MiB` : `${(file.size / 1024).toFixed(1)} KiB`;
      selection.textContent = `${file.name} · ${size}`;
    }
  };

  input.addEventListener('change', showSelection);
  for (const type of ['dragenter', 'dragover']) {
    zone.addEventListener(type, (event) => {
      event.preventDefault();
      zone.classList.add('dragover');
    });
  }
  zone.addEventListener('dragleave', (event) => {
    if (!zone.contains(event.relatedTarget)) zone.classList.remove('dragover');
  });
  zone.addEventListener('drop', (event) => {
    event.preventDefault();
    zone.classList.remove('dragover');
    const dropped = event.dataTransfer.files;
    if (dropped.length !== 1) {
      selection.textContent = '파일을 한 번에 하나씩 선택해 주세요';
      return;
    }
    try {
      input.files = dropped;
      showSelection();
    } catch (_) {
      selection.textContent = '이 브라우저에서는 파일 선택 버튼을 이용해 주세요';
    }
  });
  uploadForm.addEventListener('submit', (event) => {
    showSelection();
    if (!input.checkValidity()) {
      event.preventDefault();
      input.reportValidity();
      return;
    }
    submit.disabled = true;
    submit.textContent = '업로드 중…';
    uploadForm.setAttribute('aria-busy', 'true');
  });
  // Restore a usable button after navigating back through the browser cache.
  window.addEventListener('pageshow', () => {
    submit.disabled = false;
    submit.textContent = '업로드하기';
    uploadForm.removeAttribute('aria-busy');
    showSelection();
  });
}
