{ pkgs, ... }:

{
  programs.nixvim = {
    enable = true;
    defaultEditor = true;

    # --- 一般設定 ---
    opts = {
      number = true;
      relativenumber = true;
      shiftwidth = 2;
      tabstop = 2;
      expandtab = true;
      smartindent = true;
      wrap = true;
      linebreak = true;
      breakindent = true;
      clipboard = "unnamedplus";
      ignorecase = true;
      smartcase = true;
      termguicolors = true;
      signcolumn = "yes";
      cursorline = true;
      scrolloff = 8;
      updatetime = 250;
      undofile = true;
      splitright = true;
      splitbelow = true;
    };

    globals.mapleader = " ";
    globals.maplocalleader = " ";

    # --- IME 制御 (fcitx5) ---
    autoCmd = [
      {
        event = "VimEnter";
        pattern = "*";
        command = "silent !fcitx5-remote -c";
      }
      {
        event = "FocusGained";
        pattern = "*";
        command = "silent !fcitx5-remote -c";
      }
      {
        event = "InsertEnter";
        pattern = "*";
        command = "silent !fcitx5-remote -o";
      }
      {
        event = "InsertLeave";
        pattern = "*";
        command = "silent !fcitx5-remote -c";
      }
      {
        event = "CmdlineLeave";
        pattern = "*";
        command = "silent !fcitx5-remote -c";
      }
    ];

    # --- テーマ ---
    colorschemes.catppuccin = {
      enable = true;
      settings = {
        flavour = "mocha";
        transparent_background = true;
        integrations = {
          cmp = true;
          gitsigns = true;
          neotree = true;
          treesitter = true;
          which_key = true;
          telescope.enabled = true;
          indent_blankline.enabled = true;
          native_lsp.enabled = true;
        };
      };
    };

    # --- LSP ---
    plugins.lsp = {
      enable = true;
      servers = {
        nil_ls = {
          enable = true;
          settings.formatting.command = [ "nixfmt" ];
        };
        pyright.enable = true;
        ruff.enable = true;
        rust_analyzer = {
          enable = true;
          installCargo = false;
          installRustc = false;
        };
        ts_ls.enable = true;
        lua_ls.enable = true;
        html.enable = true;
        cssls.enable = true;
        jsonls.enable = true;
        yamlls.enable = true;
        bashls.enable = true;
        dockerls.enable = true;
        marksman.enable = true;
      };
    };

    # --- Treesitter ---
    plugins.treesitter = {
      enable = true;
      settings = {
        highlight.enable = true;
        indent.enable = true;
      };
    };

    # --- Telescope ---
    plugins.telescope = {
      enable = true;
      extensions.fzf-native.enable = true;
    };

    # --- 補完 ---
    plugins.cmp = {
      enable = true;
      settings = {
        snippet.expand = ''
          function(args)
            require('luasnip').lsp_expand(args.body)
          end
        '';
        mapping = {
          "<C-n>" = "cmp.mapping.select_next_item()";
          "<C-p>" = "cmp.mapping.select_prev_item()";
          "<C-b>" = "cmp.mapping.scroll_docs(-4)";
          "<C-f>" = "cmp.mapping.scroll_docs(4)";
          "<C-Space>" = "cmp.mapping.complete()";
          "<C-e>" = "cmp.mapping.abort()";
          "<CR>" = "cmp.mapping.confirm({ select = true })";
          "<Tab>" = ''
            cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_next_item()
              elseif require('luasnip').expand_or_jumpable() then
                require('luasnip').expand_or_jump()
              else
                fallback()
              end
            end, { 'i', 's' })
          '';
          "<S-Tab>" = ''
            cmp.mapping(function(fallback)
              if cmp.visible() then
                cmp.select_prev_item()
              elseif require('luasnip').jumpable(-1) then
                require('luasnip').jump(-1)
              else
                fallback()
              end
            end, { 'i', 's' })
          '';
        };
        sources = [
          { name = "nvim_lsp"; }
          { name = "luasnip"; }
          { name = "path"; }
          { name = "buffer"; }
        ];
      };
    };
    plugins.cmp-nvim-lsp.enable = true;
    plugins.cmp-path.enable = true;
    plugins.cmp-buffer.enable = true;
    plugins.luasnip = {
      enable = true;
      fromVscode = [{}];
    };
    plugins.friendly-snippets.enable = true;

    # --- Lualine ---
    plugins.lualine = {
      enable = true;
      settings.options.theme = "catppuccin-nvim";
    };

    # --- Neo-tree ---
    plugins.neo-tree = {
      enable = true;
      settings.close_if_last_window = true;
    };

    # --- Git ---
    plugins.gitsigns = {
      enable = true;
      settings.current_line_blame = true;
    };
    plugins.neogit.enable = true;
    plugins.diffview.enable = true;

    # --- フォーマッター ---
    plugins.conform-nvim = {
      enable = true;
      settings = {
        format_on_save = {
          timeout_ms = 2000;
          lsp_format = "fallback";
        };
        formatters_by_ft = {
          nix = [ "nixfmt" ];
          python = [ "ruff_format" ];
          javascript = [ "prettierd" ];
          typescript = [ "prettierd" ];
          javascriptreact = [ "prettierd" ];
          typescriptreact = [ "prettierd" ];
          html = [ "prettierd" ];
          css = [ "prettierd" ];
          json = [ "prettierd" ];
          yaml = [ "prettierd" ];
          markdown = [ "prettierd" ];
          lua = [ "stylua" ];
          sh = [ "shfmt" ];
          bash = [ "shfmt" ];
        };
      };
    };

    # --- DAP (デバッガー) ---
    plugins.dap.enable = true;
    plugins.dap-ui.enable = true;
    plugins.dap-virtual-text.enable = true;

    # --- ユーティリティ ---
    plugins.which-key.enable = true;
    plugins.nvim-autopairs.enable = true;
    plugins.comment.enable = true;
    plugins.indent-blankline.enable = true;
    plugins.web-devicons.enable = true;
    plugins.sleuth.enable = true;
    plugins.todo-comments.enable = true;

    # --- マークダウン ---
    plugins.render-markdown = {
      enable = true;
      settings = {
        completions.lsp.enabled = true;
        heading.icons = [ "# " "## " "### " "#### " "##### " "###### " ];
        bullet.icons = [ "-" ];
      };
    };
    plugins.markdown-preview = {
      enable = true;
      settings.auto_close = 1;
    };

    # --- キーマップ ---
    keymaps = [
      # Telescope
      { mode = "n"; key = "<leader>ff"; action = "<cmd>Telescope find_files<CR>"; options.desc = "ファイル検索"; }
      { mode = "n"; key = "<leader>fg"; action = "<cmd>Telescope live_grep<CR>"; options.desc = "テキスト検索"; }
      { mode = "n"; key = "<leader>fb"; action = "<cmd>Telescope buffers<CR>"; options.desc = "バッファ一覧"; }
      { mode = "n"; key = "<leader>fh"; action = "<cmd>Telescope help_tags<CR>"; options.desc = "ヘルプ検索"; }
      { mode = "n"; key = "<leader>fr"; action = "<cmd>Telescope oldfiles<CR>"; options.desc = "最近のファイル"; }
      { mode = "n"; key = "<leader>fd"; action = "<cmd>Telescope diagnostics<CR>"; options.desc = "診断一覧"; }

      # Neo-tree
      { mode = "n"; key = "<leader>e"; action = "<cmd>Neotree toggle<CR>"; options.desc = "ファイルツリー"; }

      # LSP
      { mode = "n"; key = "gd"; action = "<cmd>lua vim.lsp.buf.definition()<CR>"; options.desc = "定義へジャンプ"; }
      { mode = "n"; key = "gD"; action = "<cmd>lua vim.lsp.buf.declaration()<CR>"; options.desc = "宣言へジャンプ"; }
      { mode = "n"; key = "gi"; action = "<cmd>lua vim.lsp.buf.implementation()<CR>"; options.desc = "実装へジャンプ"; }
      { mode = "n"; key = "gr"; action = "<cmd>Telescope lsp_references<CR>"; options.desc = "参照一覧"; }
      { mode = "n"; key = "K"; action = "<cmd>lua vim.lsp.buf.hover()<CR>"; options.desc = "ホバー情報"; }
      { mode = "n"; key = "<leader>ca"; action = "<cmd>lua vim.lsp.buf.code_action()<CR>"; options.desc = "コードアクション"; }
      { mode = "n"; key = "<leader>cr"; action = "<cmd>lua vim.lsp.buf.rename()<CR>"; options.desc = "リネーム"; }
      { mode = "n"; key = "<leader>cf"; action = "<cmd>lua require('conform').format()<CR>"; options.desc = "フォーマット"; }

      # 診断
      { mode = "n"; key = "[d"; action = "<cmd>lua vim.diagnostic.goto_prev()<CR>"; options.desc = "前の診断"; }
      { mode = "n"; key = "]d"; action = "<cmd>lua vim.diagnostic.goto_next()<CR>"; options.desc = "次の診断"; }

      # Git
      { mode = "n"; key = "<leader>gg"; action = "<cmd>Neogit<CR>"; options.desc = "Neogit を開く"; }

      # DAP
      { mode = "n"; key = "<leader>db"; action = "<cmd>lua require('dap').toggle_breakpoint()<CR>"; options.desc = "ブレークポイント"; }
      { mode = "n"; key = "<leader>dc"; action = "<cmd>lua require('dap').continue()<CR>"; options.desc = "デバッグ続行"; }
      { mode = "n"; key = "<leader>do"; action = "<cmd>lua require('dap').step_over()<CR>"; options.desc = "ステップオーバー"; }
      { mode = "n"; key = "<leader>di"; action = "<cmd>lua require('dap').step_into()<CR>"; options.desc = "ステップイン"; }
      { mode = "n"; key = "<leader>du"; action = "<cmd>lua require('dapui').toggle()<CR>"; options.desc = "DAP UI トグル"; }

      # マークダウン
      { mode = "n"; key = "<leader>mp"; action = "<cmd>MarkdownPreview<CR>"; options.desc = "MD プレビュー"; }
      { mode = "n"; key = "<leader>mr"; action = "<cmd>RenderMarkdown toggle<CR>"; options.desc = "MD 装飾トグル"; }

      # バッファ
      { mode = "n"; key = "<leader>bd"; action = "<cmd>bdelete<CR>"; options.desc = "バッファを閉じる"; }

      # ウィンドウ分割
      { mode = "n"; key = "<leader>sv"; action = "<cmd>vsplit<CR>"; options.desc = "縦分割"; }
      { mode = "n"; key = "<leader>sh"; action = "<cmd>split<CR>"; options.desc = "横分割"; }

      # ESC でハイライト解除
      { mode = "n"; key = "<Esc>"; action = "<cmd>nohlsearch<CR>"; options.desc = "ハイライト解除"; }
    ];

    # --- extraPackages ---
    extraPackages = with pkgs; [
      nixfmt
      prettierd
      stylua
      shfmt
      ruff
      ripgrep
      fd
    ];
  };
}
