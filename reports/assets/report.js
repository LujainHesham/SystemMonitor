(function(){
  // Tab switching logic
  const tabs = document.querySelectorAll('.tablinks');
  const contents = document.querySelectorAll('.tabcontent');
  
  function openTab(tabName) {
    contents.forEach(c => c.style.display = 'none');
    tabs.forEach(t => t.classList.remove('active'));
    
    const target = document.getElementById(tabName);
    if (target) {
      target.style.display = 'block';
      const btn = document.querySelector(`[data-tab="${tabName}"]`);
      if (btn) btn.classList.add('active');
    }
  }
  
  tabs.forEach(tab => {
    tab.addEventListener('click', () => {
      const tabName = tab.getAttribute('data-tab');
      openTab(tabName);
    });
  });
  
  // Open first tab by default
  if (tabs.length > 0) {
    openTab(tabs[0].getAttribute('data-tab'));
  }
})();
